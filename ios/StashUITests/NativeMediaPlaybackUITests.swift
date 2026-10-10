import XCTest

/// Real AVPlayer acceptance on the isolated review simulator. The fixture is a private item
/// pointing to Apple's public HLS sample; no media is uploaded and teardown deletes its UUID.
final class NativeMediaPlaybackUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testNativeVideoPlayAndFullScreenPreservePosition() async throws {
        let title = try await makeFixture()
        let screens = A11yScreens(self)
        try screens.signIn()
        let app = screens.launch(.large, tab: .view)
        defer { app.terminate() }
        let search = app.textFields["library.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        A11yScreens.tapUntilFocused(search)
        search.typeText(title)
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                                                   "card.", title)).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20))
        card.tap()
        XCTAssertTrue(app.buttons["detail.done"].waitForExistence(timeout: 10))

        // SwiftUI/AVKit can surface the native action with a different AX element type.
        let fullscreen = app.descendants(matching: .any).matching(identifier: "detail.media.fullscreen").firstMatch
        A11yScreens.scrollIntoView(app, fullscreen)
        XCTAssertTrue(fullscreen.waitForExistence(timeout: 10))
        XCTAssertFalse(status(fullscreen).contains("state:playing"), "Opening detail must not autoplay")
        XCTAssertEqual(seconds(fullscreen), 0, accuracy: 0.5)
        let player = app.descendants(matching: .any).matching(identifier: "detail.media.player").firstMatch
        XCTAssertTrue(player.exists)
        let play = app.buttons.matching(NSPredicate(format: "label ==[c] %@", "Play")).firstMatch
        // AVKit can omit its central Play control from AX. A tap on the player can either
        // activate that control or reveal the native chrome; accept only observed playback
        // or a real, hittable Play button before continuing.
        player.tap()
        let startedOrReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.status(fullscreen).contains("state:playing") || (play.exists && play.isHittable)
        }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [startedOrReady], timeout: 30), .completed,
                       "The player tap must start playback or reveal its native Play control")
        if !status(fullscreen).contains("state:playing") { play.tap() }
        waitForPlayback(fullscreen, after: 5)
        screens.attachScreenshot(named: "detail-native-video-playing")

        let before = seconds(fullscreen)
        fullscreen.tap()
        let close = app.buttons["detail.media.closeFullscreen"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        screens.attachScreenshot(named: "detail-native-video-fullscreen")
        try await Task.sleep(for: .seconds(3))
        close.tap()
        XCTAssertTrue(fullscreen.waitForExistence(timeout: 10))
        let returned = seconds(fullscreen)
        XCTAssertGreaterThanOrEqual(returned, before,
                                    "Returning from full screen must preserve the existing position, not restart")
        waitForPlayback(fullscreen, after: returned + 1)
        app.buttons["detail.done"].tap()
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        XCTAssertFalse(fullscreen.exists, "Dismissal must remove the player stage")
    }

    // Apple HLS examples: https://developer.apple.com/streaming/examples/
    private static let mediaURL = "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8"
    private struct FixtureError: Error { let method: String; let status: Int }

    private func makeFixture() async throws -> String {
        let environment = ProcessInfo.processInfo.environment
        let email = try XCTUnwrap(environment["STASH_TEST_EMAIL"])
        let password = try XCTUnwrap(environment["STASH_TEST_PASSWORD"])
        let data = try await request("auth/v1/token?grant_type=password", method: "POST",
                                     body: ["email": email, "password": password])
        let auth = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let token = try XCTUnwrap(auth["access_token"] as? String)
        let userID = try XCTUnwrap((auth["user"] as? [String: Any])?["id"] as? String)
        let id = UUID().uuidString
        let title = "UITEST-NATIVE-VIDEO-\(id.prefix(8))"
        addTeardownBlock {
            _ = try await self.request("rest/v1/items?id=eq.\(id)&user_id=eq.\(userID)", method: "DELETE", token: token)
        }
        _ = try await request("rest/v1/items", method: "POST", token: token, body: [
            "id": id, "user_id": userID, "type": "video", "title": title,
            "file_path": Self.mediaURL, "mime_type": "application/vnd.apple.mpegurl", "is_public": false,
            "summary": "UI TEST fixture for native playback of Apple's public Bip Bop sample.",
            "attributes": ["enrichment": ["status": "complete"]]
        ])
        return title
    }

    private func request(_ path: String, method: String, token: String? = nil,
                         body: [String: Any]? = nil) async throws -> Data {
        var request = URLRequest(url: URL(string: path, relativeTo: StashTestProject.baseURL.appendingPathComponent("/"))!)
        request.httpMethod = method
        request.setValue(StashTestProject.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token ?? StashTestProject.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        // Match existing REST bookkeeping: three tries, one second apart. Never replay an
        // insertion whose response may have been lost after the server committed the fixture.
        let retryable = method == "DELETE" || (method == "POST" && path == "auth/v1/token?grant_type=password")
        var tries = 1
        while true {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                guard (200..<300).contains(status) else { throw FixtureError(method: method, status: status) }
                return data
            } catch let error as URLError where retryable && error.code != .cancelled && tries < 3 {
                print("Native media fixture REST retry after URLError \(error.code.rawValue)")
                tries += 1
                try await Task.sleep(for: .seconds(1))
            }
        }
    }

    @MainActor private func waitForPlayback(_ action: XCUIElement, after second: Double) {
        let advancing = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.status(action).contains("state:playing") && self.seconds(action) > second
        }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [advancing], timeout: 30), .completed,
                       "AVPlayer must report playing and its clock must advance")
    }
    @MainActor private func status(_ element: XCUIElement) -> String { element.value as? String ?? "" }
    @MainActor private func seconds(_ element: XCUIElement) -> Double {
        Double(status(element).components(separatedBy: "time:").last ?? "") ?? 0
    }
}
