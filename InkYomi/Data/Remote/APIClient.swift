import Foundation
import os.log

private let apiLogger = Logger(subsystem: "shop.inkcolors.InkYomi", category: "API")

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

struct Endpoint {
    let path: String
    let method: HTTPMethod
    let body: Encodable?
    let queryItems: [URLQueryItem]?

    init(path: String, method: HTTPMethod = .get, body: Encodable? = nil, queryItems: [URLQueryItem]? = nil) {
        self.path = path
        self.method = method
        self.body = body
        self.queryItems = queryItems
    }
}

enum APIError: Error, LocalizedError {
    case invalidURL
    case httpError(statusCode: Int, data: Data)
    case decodingError(Error)
    case unauthorized
    case rateLimited
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Invalid URL"
        case .httpError(let code, _): serverMessage ?? "HTTP error \(code)"
        case .decodingError(let error): "Decoding error: \(error.localizedDescription)"
        case .unauthorized: "Unauthorized"
        case .rateLimited: "Rate limited"
        case .networkError(let error): "Network error: \(error.localizedDescription)"
        }
    }

    /// The human-readable message the backend put in an error response body,
    /// if any. The API returns errors as JSON `{ "error": "..." }` and
    /// occasionally as problem+json `{ "title": "..." }`; we try both. Only
    /// `.httpError` carries a body, so every other case returns nil.
    var serverMessage: String? {
        guard case .httpError(_, let data) = self else { return nil }
        return Self.decodeServerMessage(from: data)
    }

    private static func decodeServerMessage(from data: Data) -> String? {
        struct ServerError: Decodable {
            let error: String?
            let title: String?
            let message: String?
        }
        guard let decoded = try? JSONDecoder().decode(ServerError.self, from: data) else {
            return nil
        }
        // Prefer a human-readable `message` (e.g. the device-limit 409's
        // "Remove a device to add this one.") over the machine `error` code.
        if let message = decoded.message, !message.isEmpty { return message }
        if let error = decoded.error, !error.isEmpty { return error }
        if let title = decoded.title, !title.isEmpty { return title }
        return nil
    }
}

actor APIClient {
    let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    var tokenProvider: (@Sendable () async -> String?)?
    var deviceIdProvider: (@Sendable () async -> String?)?

    init(
        baseURL: URL = Constants.baseURL,
        tokenProvider: (@Sendable () async -> String?)? = nil,
        deviceIdProvider: (@Sendable () async -> String?)? = nil
    ) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.deviceIdProvider = deviceIdProvider

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = Constants.httpTimeoutSeconds
        config.timeoutIntervalForResource = Constants.httpTimeoutSeconds
        self.session = URLSession(configuration: config)

        // The server uses camelCase for auth responses and snake_case
        // for catalog/other endpoints. convertFromSnakeCase handles both
        // (passes camelCase through, converts snake_case to camelCase).
        // The encoder does NOT use convertToSnakeCase — request DTOs
        // supply explicit CodingKeys where the server expects snake_case.
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

    func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T {
        let data = try await requestData(endpoint)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            apiLogger.error("DECODE ERROR [\(endpoint.path)] -> \(String(describing: T.self))")
            apiLogger.error("Error: \(String(describing: error))")
            if let json = String(data: data, encoding: .utf8) {
                apiLogger.error("RAW (first 1000): \(String(json.prefix(1000)))")
            }
            throw APIError.decodingError(error)
        }
    }

    func requestVoid(_ endpoint: Endpoint) async throws {
        _ = try await requestData(endpoint)
    }

    func requestData(_ endpoint: Endpoint) async throws -> Data {
        let request = try await buildRequest(for: endpoint)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError(URLError(.badServerResponse))
        }

        switch httpResponse.statusCode {
        case 200...299:
            return data
        case 401:
            // Preserve the body when the device has been revoked so the auth
            // layer can classify it as a terminal failure (sign out + wipe all
            // local data). Other 401s stay an opaque .unauthorized.
            if let body = String(data: data, encoding: .utf8), body.contains("device_revoked") {
                throw APIError.httpError(statusCode: 401, data: data)
            }
            throw APIError.unauthorized
        case 429:
            throw APIError.rateLimited
        default:
            throw APIError.httpError(statusCode: httpResponse.statusCode, data: data)
        }
    }

    private func buildRequest(for endpoint: Endpoint) async throws -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(endpoint.path), resolvingAgainstBaseURL: true)
        if let queryItems = endpoint.queryItems {
            components?.queryItems = queryItems
        }
        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let tokenProvider, let token = await tokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let deviceIdProvider, let deviceId = await deviceIdProvider() {
            request.setValue(deviceId, forHTTPHeaderField: "X-Device-Id")
        }

        if let body = endpoint.body {
            request.httpBody = try encoder.encode(AnyEncodable(body))
        }

        return request
    }
}

// Type-erasing wrapper for Encodable
private struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void

    init(_ value: Encodable) {
        _encode = { encoder in
            try value.encode(to: encoder)
        }
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}
