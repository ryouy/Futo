import Foundation

/// サーバーAPIのエラー。トークンや個人の統計は、ここにも、ログにも入れない。
struct APIError: Error, Equatable {
    enum Kind: Equatable {
        case notConfigured      // アプリ側、またはサーバー側が未設定
        case offline            // 通信できない
        case unauthorized       // ログインが必要・失効
        case forbidden
        case notFound
        case gone               // 期限切れ・使用済み
        case conflict           // 同時操作の競合（もう一度試せる）
        case rateLimited
        case invalid            // 入力が不正
        case server
    }

    var kind: Kind
    /// サーバーが返した、分類済みのコード（例：daily_limit）。なければ nil
    var code: String?
}

/// 共有・フレンドのAPIクライアント。Authorization: Bearer <Firebase IDトークン> を付ける。
final class APIClient {
    /// 引数は「強制的に更新するか」。nil を返すと、ログインしていない扱い。
    typealias TokenProvider = (_ forceRefresh: Bool) async throws -> String?

    private let baseURL: URL?
    private let session: URLSession
    private let tokenProvider: TokenProvider

    init(baseURL: URL?, session: URLSession = .shared, tokenProvider: @escaping TokenProvider) {
        self.baseURL = baseURL
        self.session = session
        self.tokenProvider = tokenProvider
    }

    func send<T: Decodable>(
        _ method: String, _ path: String, body: (any Encodable)? = nil,
        authenticated: Bool = true, as type: T.Type = T.self
    ) async throws -> T {
        let (data, _) = try await perform(method, path, body: body, authenticated: authenticated, allowRefresh: true)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError(kind: .server, code: "invalid_response")
        }
    }

    private func perform(_ method: String, _ path: String, body: (any Encodable)?, authenticated: Bool, allowRefresh: Bool) async throws -> (Data, HTTPURLResponse) {
        guard let baseURL, let url = URL(string: path, relativeTo: baseURL) else { throw APIError(kind: .notConfigured, code: nil) }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(AnyEncodable(body))
        }
        if authenticated {
            guard let token = try await tokenProvider(!allowRefresh) else { throw APIError(kind: .unauthorized, code: nil) }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw APIError(kind: error.code == .notConnectedToInternet || error.code == .networkConnectionLost || error.code == .timedOut || error.code == .cannotConnectToHost ? .offline : .server, code: nil)
        }
        guard let http = response as? HTTPURLResponse else { throw APIError(kind: .server, code: nil) }
        if (200..<300).contains(http.statusCode) { return (data, http) }

        let code = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
        // トークンが古いだけかもしれないので、1回だけ更新して再試行する
        if http.statusCode == 401, authenticated, allowRefresh {
            return try await perform(method, path, body: body, authenticated: authenticated, allowRefresh: false)
        }
        throw APIError(kind: Self.kind(for: http.statusCode, code: code), code: code)
    }

    static func kind(for status: Int, code: String?) -> APIError.Kind {
        switch status {
        case 400, 413: return .invalid
        case 401: return .unauthorized
        case 403: return .forbidden
        case 404: return .notFound
        case 409: return .conflict
        case 410: return .gone
        case 429: return .rateLimited
        case 503 where code == "not_configured": return .notConfigured
        default: return .server
        }
    }
}

/// `any Encodable` をそのまま符号化するための包み。
private struct AnyEncodable: Encodable {
    let value: any Encodable
    init(_ value: any Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}
