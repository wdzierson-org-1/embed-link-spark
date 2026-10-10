import UIKit
import XCTest

/// Run only on the dedicated QA simulator with injected review-account credentials.
/// Every write targets the UUID created here; existing review fixtures are never modified.
final class ItemLinkSharingUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testPrivateItemLinkCanBeCopiedAndReopenedWithoutPublishingToFeed() async throws {
        let environment = ProcessInfo.processInfo.environment
        let email = try XCTUnwrap(environment["STASH_TEST_EMAIL"])
        let password = try XCTUnwrap(environment["STASH_TEST_PASSWORD"])
        let rest = try await ShareFixtureSession.signIn(email: email, password: password)
        let id = UUID().uuidString.lowercased()
        let title = "UITEST-LINKSHARE: \(id.prefix(8))"
        // Register before POST so an uncertain insert response still gets exact-ID cleanup.
        addTeardownBlock { try await rest.deleteItem(id: id) }
        try await rest.insertItem(id: id, title: title)

        let screens = A11yScreens(self)
        try screens.signIn()
        let app = screens.launch(.large, tab: .view, arguments: ["--uitest-reduce-motion"])
        defer { app.terminate() }
        let onboarding = app.buttons["onboarding.skip"]
        if onboarding.waitForExistence(timeout: 3) { onboarding.tap() }
        let search = app.textFields["library.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        A11yScreens.tapUntilFocused(search)
        search.typeText(title)
        let card = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier MATCHES %@ AND label CONTAINS %@", #"card\.[0-9]+"#, title))
            .firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20), "The disposable item should be searchable")
        card.tap()
        let share = app.buttons["detail.share"]
        XCTAssertTrue(share.waitForExistence(timeout: 10))
        // Give appearance reads time to finish: simply opening detail must never mint a link.
        try await Task.sleep(for: .milliseconds(700))
        let opened = try await rest.item(id: id)
        XCTAssertNil(opened.shareToken)
        XCTAssertNil(opened.sharedAt)
        XCTAssertFalse(opened.isPublic)

        share.tap()
        let address = app.staticTexts["detail.share.url"]
        XCTAssertTrue(address.waitForExistence(timeout: 20), "Explicit Share should create a link")
        let shared = try await rest.item(id: id)
        let token = try XCTUnwrap(shared.shareToken)
        XCTAssertNotNil(shared.sharedAt)
        XCTAssertNotNil(token.range(of: #"^[A-Za-z0-9]{10}$"#, options: .regularExpression))
        XCTAssertFalse(shared.isPublic, "An unlisted link must not publish the item to the feed")
        let url = "https://www.gostash.it/s/\(token)"
        XCTAssertEqual(address.label, url)
        let anonymous = try await rest.sharedItem(token: token)
        XCTAssertEqual(anonymous.map(\.id), [id])
        XCTAssertEqual(anonymous.first?.title, title)
        XCTAssertEqual(anonymous.first?.content, "Disposable share-link test note")

        let copy = app.buttons["detail.share.copy"]
        let copyReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: copy)
        XCTAssertEqual(XCTWaiter().wait(for: [copyReady], timeout: 10), .completed)
        XCTAssertTrue(copy.isHittable)
        copy.tap()
        let copied = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Link copied"), object: copy)
        XCTAssertEqual(XCTWaiter().wait(for: [copied], timeout: 5), .completed)
        // Do not read UIPasteboard from the separate UI-test runner: iOS presents a paste
        // permission prompt and blocks an unattended run. The displayed URL and the real
        // Copy confirmation cover the interaction without accepting a cross-app prompt.
        XCTAssertFalse(app.buttons["detail.share.system"].exists)
        XCTAssertFalse(app.buttons["detail.share.revoke"].exists)
        XCTAssertFalse(app.buttons["detail.share.done"].exists)
        let close = app.buttons["detail.share.close"]
        XCTAssertTrue(close.isHittable, "The compact panel must provide a reachable close button")
        screens.attachScreenshot(named: "item-link-sharing")
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 5))
        let afterClose = try await rest.item(id: id)
        XCTAssertEqual(afterClose.shareToken, token, "Closing the panel must not revoke the link")
        XCTAssertEqual(afterClose.sharedAt, shared.sharedAt)
        XCTAssertFalse(afterClose.isPublic)

        XCTAssertTrue(share.isHittable)
        share.tap()
        XCTAssertTrue(address.waitForExistence(timeout: 10))
        XCTAssertEqual(address.label, url)
        let reopened = try await rest.item(id: id)
        XCTAssertEqual(reopened.shareToken, token, "Reopening the panel must reuse the existing link")
        XCTAssertEqual(reopened.sharedAt, shared.sharedAt)
        XCTAssertFalse(reopened.isPublic)
        XCTAssertEqual(reopened.content, "Disposable share-link test note")
        let existingLink = try await rest.sharedItem(token: token)
        XCTAssertEqual(existingLink.map(\.id), [id])
        let reopenedCopyReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: copy)
        XCTAssertEqual(XCTWaiter().wait(for: [reopenedCopyReady], timeout: 10), .completed)
        XCTAssertTrue(copy.isHittable)
        XCTAssertEqual(copy.label, "Copy link", "A new presentation starts with the Copy action")
        copy.tap()
        let copiedAgain = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Link copied"), object: copy)
        XCTAssertEqual(XCTWaiter().wait(for: [copiedAgain], timeout: 5), .completed)
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 5))
    }
}

private struct ShareFixtureSession: Sendable {
    let token: String
    let userID: String

    struct Row: Decodable {
        let id: String
        let title: String?
        let content: String?
        let isPublic: Bool
        let shareToken: String?
        let sharedAt: String?
        enum CodingKeys: String, CodingKey {
            case id, title, content
            case isPublic = "is_public", shareToken = "share_token", sharedAt = "shared_at"
        }
    }
    struct SharedRow: Decodable { let id: String; let title: String?; let content: String? }
    private struct RequestFailure: Error { let status: Int }

    static func signIn(email: String, password: String) async throws -> Self {
        struct Session: Decodable { let access_token: String; let user: User }
        struct User: Decodable { let id: String }
        let url = StashTestProject.baseURL.appending(path: "/auth/v1/token")
            .appending(queryItems: [.init(name: "grant_type", value: "password")])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(StashTestProject.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        let session = try JSONDecoder().decode(Session.self, from: await data(for: request))
        return .init(token: session.access_token, userID: session.user.id)
    }

    func insertItem(id: String, title: String) async throws {
        var request = request(path: "/rest/v1/items", method: "POST")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "id": id, "user_id": userID, "type": "link", "title": title,
            "url": "https://example.com/native-share-review/\(id)",
            "description": "Disposable item for native sharing acceptance",
            "content": "Disposable share-link test note", "summary": "Share-link test summary",
            "page_body": "Share-link test source", "is_public": false,
            "share_token": NSNull(), "shared_at": NSNull(), "attributes": [String: String]()
        ])
        let rows = try JSONDecoder().decode([Row].self, from: await Self.data(for: request))
        XCTAssertEqual(rows.map(\.id), [id])
    }

    func item(id: String) async throws -> Row {
        let query = [URLQueryItem(name: "id", value: "eq.\(id)"), .init(name: "user_id", value: "eq.\(userID)"),
                     .init(name: "select", value: "id,title,content,is_public,share_token,shared_at")]
        let rows = try JSONDecoder().decode([Row].self, from: await Self.data(for: request(path: "/rest/v1/items", query: query)))
        return try XCTUnwrap(rows.first)
    }

    func sharedItem(token: String) async throws -> [SharedRow] {
        // The anon role receives no owner token: this proves the same public read contract
        // used by /s/<token>, rather than accidentally reading through owner RLS.
        var request = request(path: "/rest/v1/rpc/shared_item", method: "POST", anonymous: true)
        request.httpBody = try JSONSerialization.data(withJSONObject: ["p_token": token])
        return try JSONDecoder().decode([SharedRow].self, from: await Self.data(for: request))
    }

    func deleteItem(id: String) async throws {
        var request = request(path: "/rest/v1/items", method: "DELETE", query: [
            .init(name: "id", value: "eq.\(id)"), .init(name: "user_id", value: "eq.\(userID)"),
            .init(name: "select", value: "id,title,content,is_public,share_token,shared_at")
        ])
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        let rows = try JSONDecoder().decode([Row].self, from: await Self.data(for: request))
        XCTAssertTrue(rows.allSatisfy { $0.id == id })
    }

    private func request(path: String, method: String = "GET", query: [URLQueryItem] = [], anonymous: Bool = false) -> URLRequest {
        var request = URLRequest(url: StashTestProject.baseURL.appending(path: path).appending(queryItems: query))
        request.httpMethod = method
        request.setValue(StashTestProject.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonymous ? StashTestProject.anonKey : token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private static func data(for request: URLRequest) async throws -> Data {
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path ?? ""
        let retryable = method == "GET" || method == "DELETE"
            || (method == "POST" && ["/rest/v1/rpc/shared_item", "/auth/v1/token"].contains(path))
        var attempt = 1
        while true {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                guard (200..<300).contains(status) else { throw RequestFailure(status: status) }
                return data
            } catch let error as URLError where retryable && attempt < 3 && error.code != .cancelled && !Task.isCancelled {
                // Retry fixture housekeeping after a transient connection loss. The insert
                // POST is deliberately excluded: an uncertain response must not replay it.
                attempt += 1
                try await Task.sleep(for: .seconds(1))
            }
        }
    }
}
