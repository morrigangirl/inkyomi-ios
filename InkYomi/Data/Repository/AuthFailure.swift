import Foundation

/// Refresh-token outcomes that are NOT success. The `terminal` flag is the
/// load-bearing bit: only terminal failures cause an automatic sign-out.
/// Everything else is treated as transient — the user stays signed in and
/// the next access-token request retries.
///
/// "Terminal" means the auth server has explicitly told us this refresh
/// token will never work again — RFC 6749 token-error JSON body containing
/// one of `invalid_grant`, `unauthorized_client`, or `invalid_token`. Or
/// there's no refresh token at all.
///
/// Network failures, timeouts, 5xx, ambiguous 401s with empty bodies, and
/// rate-limit responses are all transient.
enum AuthFailure: Error {
    case noRefreshToken
    case remoteRejected(terminal: Bool, statusCode: Int, body: String)
    case network(underlying: Error)

    var terminal: Bool {
        switch self {
        case .noRefreshToken: true
        case .remoteRejected(let terminal, _, _): terminal
        case .network: false
        }
    }

    /// Inspect an `APIError` thrown by the refresh endpoint and turn it into
    /// the appropriate `AuthFailure`. The classification is conservative —
    /// we only mark a failure terminal when the server's body explicitly
    /// names an OAuth 2.0 token-error code that means "this token is dead".
    static func classify(_ error: Error) -> AuthFailure {
        if let apiError = error as? APIError {
            switch apiError {
            case .httpError(let code, let data):
                let body = String(data: data, encoding: .utf8) ?? ""
                let terminal = isTerminalRejection(code: code, body: body)
                return .remoteRejected(terminal: terminal, statusCode: code, body: body)
            case .unauthorized:
                // 401 from the refresh endpoint without a parsed body — we
                // can't tell if it's `invalid_grant` or a flaky proxy. Be
                // permissive: stay signed in, let the user manually sign
                // out if the situation persists.
                return .remoteRejected(terminal: false, statusCode: 401, body: "")
            case .rateLimited, .networkError, .invalidURL, .decodingError:
                return .network(underlying: apiError)
            }
        }
        return .network(underlying: error)
    }

    private static func isTerminalRejection(code: Int, body: String) -> Bool {
        guard [400, 401, 403].contains(code) else { return false }
        return body.contains("\"invalid_grant\"") ||
            body.contains("\"unauthorized_client\"") ||
            body.contains("\"invalid_token\"") ||
            // The backend returns `{"error":"device_revoked"}` when this device
            // has been removed. Treat it as terminal so the app signs out and
            // wipes all local data on the next refresh after revocation.
            body.contains("device_revoked")
    }
}
