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

    public func addNote(content: String, title: String?, isPublic: Bool, accessToken: String) async throws -> Item {
        var body: [String: Any] = ["content": content, "is_public": isPublic]
        if let title { body["title"] = title }
        return try await send(path: "add-note", body: body, envelopeKey: "note", accessToken: accessToken)
    }

    public func addURL(_ url: String, note: String, isPublic: Bool, accessToken: String) async throws -> Item {
        let body: [String: Any] = ["url": url, "content": note, "is_public": isPublic]
        return try await send(path: "add-url", body: body, envelopeKey: "item", accessToken: accessToken)
    }

    public func addFile(path: String, mimeType: String, fileSize: Int?, content: String?,
                        isPublic: Bool, accessToken: String) async throws -> Item {
        var body: [String: Any] = ["file_path": path, "mime_type": mimeType, "is_public": isPublic]
        if let fileSize { body["file_size"] = fileSize }
        if let content, !content.isEmpty { body["content"] = content }
        return try await send(path: "add-file", body: body, envelopeKey: "item", accessToken: accessToken)
    }

    private func send(path: String, body: [String: Any], envelopeKey: String, accessToken: String) async throws -> Item {
        let data = try await poster.post(path: path, body: body, accessToken: accessToken)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let itemObject = root[envelopeKey],
              let itemData = try? JSONSerialization.data(withJSONObject: itemObject)
        else { throw CaptureError.malformedResponse }
        return try Item.decoder.decode(Item.self, from: itemData)
    }
}

public func makeUploadPath(userId: UUID, fileExtension: String) -> String {
    "\(userId.uuidString.lowercased())/\(UUID().uuidString.lowercased()).\(fileExtension.lowercased())"
}

public func uploadToStorage(data: Data, path: String, contentType: String) async throws {
    try await StashClient.shared.storage.from("stash-media")
        .upload(path, data: data, options: FileOptions(contentType: contentType))
}
