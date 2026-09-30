import XCTest

/// Apple's "required reason" system-boot-time APIs (`ProcessInfo.systemUptime`,
/// `mach_absolute_time()`) must be declared in a privacy manifest, or App Store Connect rejects the
/// upload (ITMS-91053). The app declares none, so none may be called: this scans the shipped
/// sources — StashKit, the app, the share extension — for them, ignoring `//` comments (which
/// explain why they're avoided). Final wave B: `ChatStore`'s stream coalescer used `systemUptime`;
/// it now reads `ContinuousClock`.
final class BootTimeAPIUsageTests: XCTestCase {
    private static let forbidden = ["systemUptime", "mach_absolute_time"]

    func testNoShippedSourceCallsABootTimeAPI() throws {
        let iosRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // StashKitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // StashKit
            .deletingLastPathComponent()   // ios
        let roots = ["StashKit/Sources", "Stash", "StashShareExtension"].map { iosRoot.appendingPathComponent($0) }
        var scanned = 0
        var hits: [String] = []
        for root in roots {
            let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }
                .filter { $0.pathExtension == "swift" } ?? []
            for file in files {
                scanned += 1
                let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: .newlines)
                for (number, line) in lines.enumerated() {
                    let code = line.components(separatedBy: "//").first ?? ""
                    for api in Self.forbidden where code.contains(api) {
                        hits.append("\(file.lastPathComponent):\(number + 1) \(api)")
                    }
                }
            }
        }
        XCTAssertGreaterThan(scanned, 50, "the scan must actually reach the sources (\(iosRoot.path))")
        XCTAssertEqual(hits, [], "undeclared required-reason boot-time API use")
    }
}
