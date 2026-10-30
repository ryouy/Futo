import Foundation

/// Drive API v3（アプリ専用領域 appDataFolder）の、バックアップ1ファイル分の操作。
struct DriveFileInfo: Equatable {
    var id: String
    var modifiedTime: Date?
    var size: Int?
}

final class DriveClient {
    typealias TokenProvider = () async throws -> String

    private let session: URLSession
    private let token: TokenProvider

    init(session: URLSession = .shared, token: @escaping TokenProvider) {
        self.session = session
        self.token = token
    }

    private static let api = "https://www.googleapis.com/drive/v3/files"
    private static let upload = "https://www.googleapis.com/upload/drive/v3/files"

    /// バックアップファイルの情報。なければ nil。
    func find() async throws -> DriveFileInfo? {
        var c = URLComponents(string: Self.api)!
        c.queryItems = [
            .init(name: "spaces", value: "appDataFolder"),
            .init(name: "q", value: "name = '\(BackupDocument.fileName)' and trashed = false"),
            .init(name: "fields", value: "files(id,modifiedTime,size)"),
            .init(name: "orderBy", value: "modifiedTime desc"),
            .init(name: "pageSize", value: "1"),
        ]
        let data = try await send(URLRequest(url: c.url!))
        struct Files: Decodable { struct F: Decodable { var id: String; var modifiedTime: String?; var size: String? }; var files: [F] }
        guard let list = try? JSONDecoder().decode(Files.self, from: data) else { throw DriveError.failed }
        guard let f = list.files.first else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        let date = f.modifiedTime.flatMap { formatter.date(from: $0) ?? plain.date(from: $0) }
        return DriveFileInfo(id: f.id, modifiedTime: date, size: f.size.flatMap(Int.init))
    }

    /// 保存する。すでにあれば上書き、なければ新規作成（アプリ専用領域に）。
    @discardableResult
    func save(_ data: Data, existing: DriveFileInfo?) async throws -> DriveFileInfo {
        var request: URLRequest
        if let existing {
            var c = URLComponents(string: "\(Self.upload)/\(existing.id)")!
            c.queryItems = [.init(name: "uploadType", value: "media"), .init(name: "fields", value: "id,modifiedTime,size")]
            request = URLRequest(url: c.url!)
            request.httpMethod = "PATCH"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = data
        } else {
            let boundary = "futo-\(UUID().uuidString)"
            var c = URLComponents(string: Self.upload)!
            c.queryItems = [.init(name: "uploadType", value: "multipart"), .init(name: "fields", value: "id,modifiedTime,size")]
            request = URLRequest(url: c.url!)
            request.httpMethod = "POST"
            request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            let metadata = try JSONSerialization.data(withJSONObject: ["name": BackupDocument.fileName, "parents": ["appDataFolder"]])
            var body = Data()
            body.append(Data("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".utf8))
            body.append(metadata)
            body.append(Data("\r\n--\(boundary)\r\nContent-Type: application/json\r\n\r\n".utf8))
            body.append(data)
            body.append(Data("\r\n--\(boundary)--".utf8))
            request.httpBody = body
        }
        let response = try await send(request)
        struct Saved: Decodable { var id: String }
        guard let saved = try? JSONDecoder().decode(Saved.self, from: response) else { throw DriveError.failed }
        return DriveFileInfo(id: saved.id, modifiedTime: Date(), size: data.count)
    }

    func download(_ file: DriveFileInfo) async throws -> Data {
        var c = URLComponents(string: "\(Self.api)/\(file.id)")!
        c.queryItems = [.init(name: "alt", value: "media")]
        return try await send(URLRequest(url: c.url!))
    }

    func delete(_ file: DriveFileInfo) async throws {
        var request = URLRequest(url: URL(string: "\(Self.api)/\(file.id)")!)
        request.httpMethod = "DELETE"
        _ = try await send(request)
    }

    private func send(_ original: URLRequest, retried: Bool = false) async throws -> Data {
        var request = original
        request.timeoutInterval = 30
        request.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost].contains(error.code) {
            throw DriveError.offline
        } catch { throw DriveError.failed }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300: return data
        case 401: throw DriveError.needsConsent
        case 403:
            // 容量の上限、またはDrive APIが無効・権限なし
            let reason = String(data: data, encoding: .utf8) ?? ""
            if reason.contains("accessNotConfigured") || reason.contains("SERVICE_DISABLED") { throw DriveError.apiDisabled }
            throw reason.contains("storageQuotaExceeded") || reason.contains("quota") ? DriveError.quota : DriveError.needsConsent
        case 404: throw DriveError.notFound
        case 429, 500..<600:
            if !retried { try? await Task.sleep(for: .seconds(1)); return try await send(original, retried: true) }
            throw DriveError.failed
        default: throw DriveError.failed
        }
    }
}
