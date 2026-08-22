import Foundation
import Supabase

public enum CaptureError: Error, Equatable { case badStatus(Int), malformedResponse }

public protocol JSONPosting: Sendable {
    func post(path: String, body: [String: Any], accessToken: String) async throws -> Data
}

/// POSTs to <supabase>/functions/v1/<path> with the platform's two auth headers.
public struct FunctionsPoster: JSONPosting {
    public init() {}
    public func post(path: String, body: [String: Any], accessToken: String) async throws -> Data {
        var request = URLRequest(url: StashConfig.supabaseURL.appending(path: "/functions/v1/\(path)"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(StashConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw CaptureError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return data
    }
}

public struct CaptureAPI: Sendable {
    let poster: JSONPosting
    public init(poster: JSONPosting = FunctionsPoster()) { self.poster = poster }

    public func addNote(content: String, title: String?, isPublic: Bool,
                        attributes: ItemAttributes? = nil, accessToken: String) async throws -> Item {
        var body: [String: Any] = ["content": content, "is_public": isPublic]
        if let title { body["title"] = title }
        addAttributes(attributes, to: &body)
        return try await send(path: "add-note", body: body, envelopeKey: "note", accessToken: accessToken)
    }

    public func addURL(_ url: String, note: String, isPublic: Bool,
                       attributes: ItemAttributes? = nil, accessToken: String) async throws -> Item {
        var body: [String: Any] = ["url": url, "content": note, "is_public": isPublic]
        addAttributes(attributes, to: &body)
        return try await send(path: "add-url", body: body, envelopeKey: "item", accessToken: accessToken)
    }

    public func addFile(path: String, mimeType: String, fileSize: Int?, content: String?, isPublic: Bool,
                        attributes: ItemAttributes? = nil, accessToken: String) async throws -> Item {
        var body: [String: Any] = ["file_path": path, "mime_type": mimeType, "is_public": isPublic]
        if let fileSize { body["file_size"] = fileSize }
        if let content, !content.isEmpty { body["content"] = content }
        addAttributes(attributes, to: &body)
        return try await send(path: "add-file", body: body, envelopeKey: "item", accessToken: accessToken)
    }

    /// Sets `body["attributes"]` only when there's actually something to send — `nil` attributes,
    /// an `.isEmpty` blob, and an encode failure (Task 3's `jsonObject()` contract: "do not send",
    /// never `[:]`, or a caller would silently wipe every attribute the row already has on the
    /// next whole-blob PATCH-replace) all collapse to the same skip via `nonEmptyJSONObject`.
    private func addAttributes(_ attributes: ItemAttributes?, to body: inout [String: Any]) {
        guard let object = attributes?.nonEmptyJSONObject else { return }
        body["attributes"] = object
    }

    private func send(path: String, body: [String: Any], envelopeKey: String, accessToken: String) async throws -> Item {
        let data = try await poster.post(path: path, body: body, accessToken: accessToken)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let itemObject = root[envelopeKey],
              let itemData = try? JSONSerialization.data(withJSONObject: itemObject)
        else { throw CaptureError.malformedResponse }
        do {
            return try Item.decoder.decode(Item.self, from: itemData)
        } catch {
            throw CaptureError.malformedResponse
        }
    }
}

public func makeUploadPath(userId: UUID, fileExtension: String) -> String {
    "\(userId.uuidString.lowercased())/\(UUID().uuidString.lowercased()).\(fileExtension.lowercased())"
}

public func uploadToStorage(data: Data, path: String, contentType: String) async throws {
    try await StashClient.shared.storage.from("stash-media")
        .upload(path, data: data, options: FileOptions(contentType: contentType))
}

/// Task 4 (Plan 5): the streaming counterpart to `uploadToStorage` above — same bucket, same
/// eventual bytes-on-the-wire, but reached via `URLSession.upload(for:fromFile:)` (the async/await
/// form of `uploadTask(with:fromFile:)`) instead of the Supabase Storage SDK client. That SDK call
/// needs the caller to already hold the file's bytes as `Data`; this one streams straight off
/// disk, which is the entire point — `Outbox.drain`'s `local_file_path` lane (a recording that may
/// be many MB) and, from Task 6, the share extension's own uploads (under a ~120 MB process
/// ceiling) can never afford to materialize a whole shared/recorded file in memory first.
///
/// Hand-builds the request against the object endpoint
/// (`/storage/v1/object/stash-media/<path>`) rather than going through the SDK — deliberately NOT
/// `StashConfig.publicStorageURL`, which builds the separate `/object/public/...` READ path used
/// to fetch an already-uploaded file back, not to write one. Headers and the non-2xx →
/// `CaptureError.badStatus` mapping mirror `FunctionsPoster.post` exactly (same two auth headers,
/// same status-code check) — the one deliberate difference is no fixed `timeoutInterval`: that
/// poster's 20s budget suits a small JSON POST, but a large file upload over a slow connection
/// can legitimately take longer, so this leaves `URLRequest`'s ordinary default in place.
public func uploadToStorageFromFile(fileURL: URL, path: String, contentType: String, accessToken: String) async throws {
    var request = URLRequest(url: StashConfig.supabaseURL.appending(path: "/storage/v1/object/stash-media/\(path)"))
    request.httpMethod = "POST"
    request.setValue(contentType, forHTTPHeaderField: "Content-Type")
    request.setValue(StashConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    let (_, response) = try await URLSession.shared.upload(for: request, fromFile: fileURL)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
        throw CaptureError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
    }
}
