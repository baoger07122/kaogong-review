import Foundation
import SwiftUI

struct AuthSession: Codable, Sendable {
    let token: String
    let email: String
}

enum APIClientError: LocalizedError {
    case invalidResponse
    case server(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "服务器返回了无法识别的响应"
        case .server(_, let message): message
        }
    }
}

struct APIClient: Sendable {
    let baseURL: URL
    let session: URLSession

    static let production = APIClient(
        baseURL: URL(string: "https://kaogong-review.onrender.com/api/")!,
        session: .shared
    )

    func register(email: String, password: String) async throws -> AuthSession {
        try await send(path: "auth/register", method: "POST", token: nil, body: ["email": email, "password": password])
    }

    func login(email: String, password: String) async throws -> AuthSession {
        try await send(path: "auth/login", method: "POST", token: nil, body: ["email": email, "password": password])
    }

    func health() async throws -> JSONValue {
        try await send(path: "health", method: "GET", token: nil, body: Optional<String>.none)
    }

    func fetchCollection(_ collection: String, token: String) async throws -> [JSONValue] {
        try await send(path: collection, method: "GET", token: token, body: Optional<String>.none)
    }

    func upsert(_ value: JSONValue, collection: String, token: String) async throws {
        let _: JSONValue = try await send(path: collection, method: "POST", token: token, body: value)
    }

    func delete(collection: String, id: String, token: String) async throws {
        let _: JSONValue = try await send(path: "\(collection)/\(id)", method: "DELETE", token: token, body: Optional<String>.none)
    }

    private func send<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        token: String?,
        body: Body?
    ) async throws -> Response {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw APIClientError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIClientError.invalidResponse }
        guard 200..<300 ~= http.statusCode else {
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = object?["error"] as? String ?? "请求失败（\(http.statusCode)）"
            throw APIClientError.server(status: http.statusCode, message: message)
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}

private struct APIClientEnvironmentKey: EnvironmentKey {
    static let defaultValue = APIClient.production
}

extension EnvironmentValues {
    var apiClient: APIClient {
        get { self[APIClientEnvironmentKey.self] }
        set { self[APIClientEnvironmentKey.self] = newValue }
    }
}
