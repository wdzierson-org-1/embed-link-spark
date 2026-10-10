import AVKit
import StashKit
import SwiftUI
import WebKit

/// A native media stage. Changing the source releases playback; opening full screen moves
/// the existing controller, preserving the player, web document, and playback position.
struct DetailMediaStage: View {
    let source: DetailMediaSource

    var body: some View { DetailMediaContent(source: source).id(source) }
}

private struct DetailMediaContent: View {
    let source: DetailMediaSource
    @StateObject private var session: DetailMediaSession
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    init(source: DetailMediaSource) {
        self.source = source
        _session = StateObject(wrappedValue: DetailMediaSession(source: source))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Propose the floor to the player itself, rather than adding empty space around
            // a smaller aspect-fit view. YouTube requires a real 200×200 CSS-pixel viewport.
            DetailMediaPlayerLayout(aspect: source.isAudio ? 2.5 : source.aspectRatio,
                                    minimumHeight: source.isAudio ? 128 : 200) {
                DetailMediaHost(session: session)
            }
            .background(.black)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("detail.media.player")

            HStack(spacing: 8) {
                Text(source.label.lowercased()).stashFont(.machine)
                    .foregroundStyle(StashColor.ink).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button { session.host?.showFullScreen() } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("Full screen")
                .accessibilityIdentifier("detail.media.fullscreen")
                #if DEBUG
                .accessibilityValue(session.debugStatus)
                #endif
                Link(destination: source.originalURL) {
                    Image(systemName: "arrow.up.right.square")
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("Open original")
                .accessibilityHint("Opens the original media if inline playback is unavailable")
                .accessibilityIdentifier("detail.media.original")
            }
            .buttonStyle(.plain).foregroundStyle(StashColor.ink)
            .padding(.leading, 12).background(StashColor.surface)

            if let failure = session.failure {
                Text(failure).stashFont(.secondary).foregroundStyle(StashColor.muted)
                    .fixedSize(horizontal: false, vertical: true).padding(12)
                    .accessibilityIdentifier("detail.media.error")
            }
        }
        .frame(maxWidth: source.portrait ? 340 : .infinity)
        .overlay(Rectangle().strokeBorder(StashColor.line, lineWidth: 1))
        .frame(maxWidth: .infinity)
        .padding(14)
        .background { StashDotGrid() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detail.mediaStage")
        .onAppear { session.openExternal = { openURL($0) } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { session.host?.pause() } }
        .onDisappear { session.host?.pause() }
    }
}

private struct DetailMediaPlayerLayout: Layout {
    let aspect: Double
    let minimumHeight: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 340
        return CGSize(width: width, height: max(minimumHeight, width / aspect))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
    }
}

@MainActor
private final class DetailMediaSession: ObservableObject {
    let source: DetailMediaSource
    @Published var failure: String?
    @Published var playbackState = "unstarted"
    @Published var seconds: Double = 0
    weak var host: DetailMediaHostController?
    var openExternal: ((URL) -> Void)?
    var debugStatus: String { "state:\(playbackState) time:\(String(format: "%.1f", seconds))" }
    init(source: DetailMediaSource) { self.source = source }
}

private struct DetailMediaHost: UIViewControllerRepresentable {
    let session: DetailMediaSession
    func makeUIViewController(context: Context) -> DetailMediaHostController {
        DetailMediaHostController(session: session)
    }
    func updateUIViewController(_ controller: DetailMediaHostController, context: Context) {}
    static func dismantleUIViewController(_ controller: DetailMediaHostController, coordinator: ()) {
        controller.shutdown()
    }
}

@MainActor
private final class DetailMediaHostController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    private let session: DetailMediaSession
    private var mediaController: UIViewController?
    private var player: AVPlayer?
    private var webView: WKWebView?
    private var observations: [NSKeyValueObservation] = []
    private var timeObserver: Any?
    private var fullScreen: UINavigationController?
    private var mediaConstraints: [NSLayoutConstraint] = []
    private var isShutdown = false
    // YouTube's mobile API-client identity is the installed bundle ID, not a fabricated site.
    private let webOrigin = URL(string: "https://" + (Bundle.main.bundleIdentifier ?? "it.gostash.stash").lowercased())!

    init(session: DetailMediaSession) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
        session.host = self
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        switch session.source {
        case .file(let url, _): configurePlayer(url)
        case .embed(let embed): configureWebPlayer(embed)
        }
        if let mediaController { mount(mediaController, in: self) }
    }

    private func configurePlayer(_ url: URL) {
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player
        let controller = AVPlayerViewController()
        controller.player = player
        controller.videoGravity = .resizeAspect
        controller.showsPlaybackControls = true
        controller.allowsPictureInPicturePlayback = false
        controller.canStartPictureInPictureAutomaticallyFromInline = false
        controller.entersFullScreenWhenPlaybackBegins = false
        mediaController = controller
        observations.append(item.observe(\.status, options: [.new]) { [weak self] item, _ in
            let failed = item.status == .failed
            Task { @MainActor in
                if failed { self?.session.failure = "This media couldn’t play here. Open the original to try another player." }
            }
        })
        observations.append(player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let state = player.timeControlStatus
            Task { @MainActor in
                self?.session.playbackState = state == .playing ? "playing" : state == .waitingToPlayAtSpecifiedRate ? "buffering" : "paused"
                if state == .playing {
                    // Set the media category only after an explicit play action.
                    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
                }
            }
        })
        #if DEBUG
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in if time.seconds.isFinite { self?.session.seconds = time.seconds } }
        }
        #endif
        // Deliberately no play(): opening the detail never starts audio or video.
    }

    private func configureWebPlayer(_ embed: DetailVideoEmbed) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = false
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.userContentController.add(WeakMediaMessageHandler(self), name: "stashMedia")
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = self
        web.uiDelegate = self
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.isScrollEnabled = false
        web.accessibilityIdentifier = "detail.media.webPlayer"
        webView = web
        let controller = UIViewController()
        controller.view = web
        mediaController = controller

        var components = URLComponents(url: embed.url, resolvingAgainstBaseURL: false)!
        if embed.provider == .youtube {
            components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "origin", value: webOrigin.absoluteString)]
        }
        let src = components.url!.absoluteString.replacingOccurrences(of: "&", with: "&amp;")
        let youtubeScript: String
        if embed.provider == .youtube {
            #if DEBUG
            let clock = "setInterval(function(){if(player&&player.getCurrentTime) report('time',player.getCurrentTime());},500);"
            #else
            let clock = ""
            #endif
            youtubeScript = """
            <script>
            var player;
            function report(event,value){window.webkit.messageHandlers.stashMedia.postMessage({event:event,value:value});}
            function onYouTubeIframeAPIReady(){player=new YT.Player('player',{events:{
              onStateChange:function(e){report('state',e.data);},onError:function(e){report('error',e.data);}
            }});\(clock)}
            </script><script src="https://www.youtube.com/iframe_api"></script>
            """
        } else { youtubeScript = "" }
        // A local document with an explicit HTTPS base supplies the required Referer.
        // No app credentials, persistent cookies, or script-to-native action bridge is exposed.
        // https://developers.google.com/youtube/terms/required-minimum-functionality
        web.loadHTMLString("""
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <meta name="referrer" content="strict-origin-when-cross-origin">
        <style>html,body{margin:0;width:100%;height:100%;background:#000}iframe{display:block;width:100%;height:100%;border:0}</style>
        </head><body><iframe id="player" title="\(embed.label)" src="\(src)"
        allow="fullscreen; encrypted-media" allowfullscreen referrerpolicy="strict-origin-when-cross-origin"></iframe>
        \(youtubeScript)</body></html>
        """, baseURL: webOrigin)
    }

    func showFullScreen() {
        guard !isShutdown, fullScreen == nil, presentedViewController == nil,
              view.window != nil, let mediaController else { return }
        let stage = DetailFullScreenMediaController(label: session.source.label)
        let navigation = UINavigationController(rootViewController: stage)
        navigation.modalPresentationStyle = .overFullScreen
        navigation.overrideUserInterfaceStyle = .dark
        stage.close = { [weak self] in self?.closeFullScreen() }
        fullScreen = navigation
        stage.loadViewIfNeeded()
        mount(mediaController, in: stage)
        present(navigation, animated: true)
    }

    private func closeFullScreen() {
        guard let navigation = fullScreen else { return }
        navigation.dismiss(animated: true) { [weak self] in
            // URL edits/detail teardown can dismantle this host during the dismissal animation.
            guard let self, !self.isShutdown else { return }
            if let mediaController = self.mediaController { self.mount(mediaController, in: self) }
            self.fullScreen = nil
        }
    }

    private func mount(_ child: UIViewController, in parent: UIViewController) {
        NSLayoutConstraint.deactivate(mediaConstraints)
        mediaConstraints = []
        child.willMove(toParent: nil)
        child.view.removeFromSuperview()
        child.removeFromParent()
        parent.addChild(child)
        child.view.translatesAutoresizingMaskIntoConstraints = false
        parent.view.addSubview(child.view)
        let guide = parent === self ? parent.view.layoutMarginsGuide : parent.view.safeAreaLayoutGuide
        // The inline player has no margins; the full-screen player respects the native bar.
        if parent === self {
            parent.viewRespectsSystemMinimumLayoutMargins = false
            parent.view.directionalLayoutMargins = .zero
        }
        mediaConstraints = [
            child.view.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            child.view.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            child.view.topAnchor.constraint(equalTo: guide.topAnchor),
            child.view.bottomAnchor.constraint(equalTo: guide.bottomAnchor)
        ]
        NSLayoutConstraint.activate(mediaConstraints)
        child.didMove(toParent: parent)
    }

    func pause() {
        player?.pause()
        webView?.pauseAllMediaPlayback(completionHandler: nil)
    }

    func shutdown() {
        guard !isShutdown else { return }
        isShutdown = true
        pause()
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        observations = []
        webView?.stopLoading()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "stashMedia")
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        NSLayoutConstraint.deactivate(mediaConstraints)
        mediaConstraints = []
        if let mediaController {
            mediaController.willMove(toParent: nil)
            mediaController.view.removeFromSuperview()
            mediaController.removeFromParent()
        }
        mediaController = nil
        player?.replaceCurrentItem(with: nil)
        fullScreen?.dismiss(animated: false)
        fullScreen = nil
        if session.host === self { session.host = nil }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failWeb(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failWeb(error) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        session.failure = "The video player stopped. Open the original to keep watching."
    }
    private func failWeb(_ error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        session.failure = "This video couldn’t load here. Open the original to watch it."
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        if action.targetFrame == nil || action.navigationType == .linkActivated {
            if action.navigationType == .linkActivated, ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                session.openExternal?(url)
            }
            decisionHandler(.cancel)
            return
        }
        if action.targetFrame?.isMainFrame == true {
            let localDocument = url.scheme == webOrigin.scheme && url.host == webOrigin.host &&
                url.port == nil && ["", "/"].contains(url.path) && url.query == nil
            decisionHandler(localDocument || url.absoluteString == "about:blank" ? .allow : .cancel)
        } else {
            // Frames may fetch provider login/CDN pages, but cannot navigate the native host.
            decisionHandler(url.scheme == "https" || url.absoluteString == "about:blank" ? .allow : .cancel)
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "stashMedia", message.frameInfo.isMainFrame,
              message.frameInfo.securityOrigin.host == webOrigin.host,
              let body = message.body as? [String: Any], let event = body["event"] as? String,
              let number = body["value"] as? NSNumber else { return }
        switch event {
        case "state":
            session.playbackState = [1: "playing", 2: "paused", 3: "buffering", 0: "ended", 5: "cued"] [number.intValue] ?? "unstarted"
        case "time":
            if number.doubleValue.isFinite, number.doubleValue >= 0 { session.seconds = number.doubleValue }
        case "error":
            session.failure = "This video can’t play in the embedded player. Open the original to watch it."
            session.playbackState = "failed:\(number.intValue)"
        default: break
        }
    }
}

@MainActor
private final class WeakMediaMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: (any WKScriptMessageHandler)?
    init(_ target: any WKScriptMessageHandler) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}

@MainActor
private final class DetailFullScreenMediaController: UIViewController {
    var close: (() -> Void)?
    init(label: String) {
        super.init(nibName: nil, bundle: nil)
        title = label
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.close?() })
        navigationItem.rightBarButtonItem?.accessibilityIdentifier = "detail.media.closeFullscreen"
    }
    override func accessibilityPerformEscape() -> Bool { close?(); return true }
}
