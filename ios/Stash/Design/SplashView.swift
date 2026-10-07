import SwiftUI

/// The web's loading interstitial: paper, the symbol and a terminal line. Animation
/// says only that the app is opening; it never invents progress through network steps.
struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var beganAt = Date()
    @State private var initialLine = 0
    @State private var didBegin = false

    private static let lines = [
        "opening your stash",
        "the door creaks open…",
        "saving made simple",
        "hello again",
        "hey, you <3",
        "you’re my favorite… shhh",
        "dusting off your finds",
        "right where you left it",
        "remembering so you don’t have to",
        "psst. it’s all still here",
        "fetching your shiny things",
        "fluffing the pillows",
    ]
    private static let cipher = Array("01#%+=?<>/[]{}")

    var body: some View {
        ZStack {
            StashPaperBackdrop(showDots: true).ignoresSafeArea()
            VStack(spacing: 32) {
                Image("StashSymbol")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 54, height: 58)
                    .foregroundStyle(StashColor.ink)
                TimelineView(.animation(minimumInterval: 0.035, paused: reduceMotion || dynamicTypeSize.isAccessibilitySize)) { context in
                    Text(loadingLine(at: context.date))
                        .stashFont(.code(.subheadline))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 24)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Opening your stash")
        }
        .onAppear {
            guard !didBegin else { return }
            didBegin = true
            let key = "stash.loading.line"
            initialLine = max(0, UserDefaults.standard.integer(forKey: key)) % Self.lines.count
            UserDefaults.standard.set((initialLine + 1) % Self.lines.count, forKey: key)
            beganAt = Date()
        }
    }

    private func loadingLine(at date: Date) -> AttributedString {
        // At accessibility sizes keep a stable line that can wrap at word boundaries.
        // Reduced Motion has the same meaningful still as the web.
        guard !reduceMotion, !dynamicTypeSize.isAccessibilitySize else {
            return AttributedString("> " + Self.lines[initialLine] + " ▌")
        }

        let elapsed = max(0, date.timeIntervalSince(beganAt))
        let totalDuration = Self.lines.reduce(0.0) { $0 + Self.duration(of: $1) }
        var remaining = elapsed.truncatingRemainder(dividingBy: totalDuration)
        var index = initialLine
        while remaining >= Self.duration(of: Self.lines[index]) {
            remaining -= Self.duration(of: Self.lines[index])
            index = (index + 1) % Self.lines.count
        }
        let characters = Array(Self.lines[index])
        let decodeDuration = Self.decodeDuration(characterCount: characters.count)
        let outgoing = remaining > decodeDuration + 1.8
        let settled: Int
        if outgoing {
            settled = max(0, Int(Double(characters.count) * (1 - (remaining - decodeDuration - 1.8) / 0.28)))
        } else {
            settled = min(characters.count, Int(Double(characters.count) * remaining / decodeDuration))
        }
        let frame = Int(elapsed / 0.035)
        var line = AttributedString("> ")
        line.foregroundColor = StashColor.ink
        for (position, character) in characters.enumerated() {
            let resolved = position < settled
            let shown = resolved || character == " " ? character : Self.cipher[(frame * 17 + position * 13) % Self.cipher.count]
            var cell = AttributedString(String(shown))
            cell.foregroundColor = resolved ? StashColor.ink : StashColor.muted
            if position == settled, !outgoing {
                cell.foregroundColor = StashColor.onSpot
                cell.backgroundColor = StashColor.spot
            }
            line.append(cell)
        }
        if settled == characters.count {
            var cursor = AttributedString(" ▌")
            cursor.foregroundColor = StashColor.ink
            line.append(cursor)
        }
        return line
    }

    private static func decodeDuration(characterCount: Int) -> Double {
        min(1.2, 0.42 + Double(characterCount) * 0.022)
    }

    private static func duration(of line: String) -> Double {
        decodeDuration(characterCount: line.count) + 1.8 + 0.28
    }
}
