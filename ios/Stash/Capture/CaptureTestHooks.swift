import Foundation

/// Launch-argument hooks for `ComposerUITests` (plan 15 6D). Every hook body is `#if DEBUG`, so a
/// Release build only ever sees the no-op answers below.
enum CaptureTestHooks {
    /// `--uitest-slow-attachment-load=<ms>`: every composer attachment load BLOCKS its loading
    /// thread for `ms` before finishing — a slow disk or iCloud read in miniature. Blocking rather
    /// than an async sleep on purpose: if a load ever ran on the main thread again, the composer
    /// would freeze for that long and `ComposerUITests` would notice typing stall.
    static func simulateSlowAttachmentLoad() {
        #if DEBUG
        if let milliseconds = intArgument("--uitest-slow-attachment-load=") {
            usleep(useconds_t(max(0, milliseconds)) * 1000)
        }
        #endif
    }

    /// `--uitest-voice-interrupt-after=<s>`: each voice recording receives a synthetic
    /// `AVAudioSession.interruptionNotification` (`.began`) `s` seconds after it starts — what a
    /// phone call or Siri delivers.
    static var voiceInterruptionDelay: Duration? {
        #if DEBUG
        return intArgument("--uitest-voice-interrupt-after=").map { .seconds($0) }
        #else
        return nil
        #endif
    }

    /// `--uitest-voice-probe`: the voice recorder sheet carries `debug.idleTimer`, which reads
    /// "disabled" while the screen is being kept awake and "enabled" otherwise.
    static var showsVoiceProbe: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--uitest-voice-probe")
        #else
        return false
        #endif
    }

    /// `--uitest-voice-gate-open`: the mic button ignores the client-side subscription gate, so
    /// the recorder itself can be tested on the lapsed test account. Those tests never save a
    /// recording (and the server enforces the gate on its own).
    static var opensVoiceGate: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--uitest-voice-gate-open")
        #else
        return false
        #endif
    }

    /// `--uitest-import-file=<name>:<MB>` (repeatable): on the composer's first appearance, sparse
    /// files of those sizes are handed to its file-import path exactly as the Files picker hands
    /// over its picks — the bytes a picker would deliver, minus the out-of-process picker UI.
    /// Consumed once per launch. Empty in Release.
    @MainActor
    static func takeSyntheticImports() -> [URL] {
        #if DEBUG
        guard !syntheticImportsTaken else { return [] }
        syntheticImportsTaken = true
        let prefix = "--uitest-import-file="
        let directory = URL.temporaryDirectory.appending(path: "uitest-imports-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return ProcessInfo.processInfo.arguments.filter { $0.hasPrefix(prefix) }.compactMap { argument in
            let spec = argument.dropFirst(prefix.count).split(separator: ":")
            guard spec.count == 2, let megabytes = UInt64(spec[1]) else { return nil }
            let url = directory.appending(path: String(spec[0]))
            guard FileManager.default.createFile(atPath: url.path, contents: nil),
                  let handle = try? FileHandle(forWritingTo: url) else { return nil }
            defer { try? handle.close() }
            try? handle.truncate(atOffset: megabytes * 1_048_576)
            return url
        }
        #else
        return []
        #endif
    }

    #if DEBUG
    @MainActor private static var syntheticImportsTaken = false

    private static func intArgument(_ prefix: String) -> Int? {
        ProcessInfo.processInfo.arguments.first { $0.hasPrefix(prefix) }.flatMap { Int($0.dropFirst(prefix.count)) }
    }
    #endif
}
