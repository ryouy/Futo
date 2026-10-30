import Foundation
import Observation

/// Google Driveのバックアップ・復元の状態と操作。手動だけ（自動の同期はしない）。
/// 成功は、Driveが成功を返したときだけ表示する。
@MainActor
@Observable
final class BackupModel {
    enum Phase: Equatable { case idle, working }

    struct RestorePreview: Equatable {
        var createdAt: Date
        var totalSessions: Int
        var newSessions: Int
        var skippedSessions: Int
        var newCards: Int
    }

    let drive: DriveAuthService
    @ObservationIgnored private let sharing: SharingModel
    @ObservationIgnored let app: AppModel
    @ObservationIgnored private let client: DriveClient

    private(set) var phase: Phase = .idle
    /// Drive上のバックアップ（なければ nil）。`refresh()` のあとに確定する
    private(set) var remote: DriveFileInfo?
    private(set) var checkedRemote = false
    private(set) var lastBackupAt: Date?
    /// 復元の確認用。ユーザーが承認するまで、端末は変えない
    private(set) var preview: RestorePreview?
    @ObservationIgnored private var pendingDocument: BackupDocument?
    @ObservationIgnored private var pendingPlan: BackupMergePlan?
    var message: String?
    var resultMessage: String?

    init(sharing: SharingModel, app: AppModel, urlSession: URLSession = .shared, drive: DriveAuthService? = nil) {
        self.sharing = sharing
        self.app = app
        let service = drive ?? DriveAuthService(config: sharing.config, urlSession: urlSession, web: WebAuthRunner(), store: KeychainDriveTokenStore())
        self.drive = service
        let share = sharing
        self.client = DriveClient(session: urlSession) { [weak service] in
            guard let service, let uid = share.uid else { throw DriveError.needsConsent }
            return try await service.accessToken(uid: uid)
        }
        service.refreshConnection(uid: sharing.uid)
    }

    var isConnected: Bool { drive.connectedUID != nil && drive.connectedUID == sharing.uid }
    var isWorking: Bool { phase == .working }
    var canBackup: Bool { app.mode == .device }

    func syncConnection() { drive.refreshConnection(uid: sharing.uid) }

    // MARK: 接続

    func connect() async {
        guard let uid = sharing.uid else { return }
        await run {
            try await self.drive.connect(uid: uid)
            try await self.loadRemote()
            if self.remote != nil {
                // すでにバックアップがあるときは、上書きしない（新しい端末で、空の記録に置き換えてしまわないため）
                self.resultMessage = tr("Driveに、すでにバックアップがあります。上書きしないよう、自動のバックアップはしていません。必要なら「バックアップから戻す」を使ってください。")
            } else if self.canBackup {
                // 有効にしたら、最初の1回を自動で保存する
                try await self.performBackup()
            } else {
                self.resultMessage = tr("バックアップを有効にしました。デモモードの記録は、保存されません。")
            }
        }
    }

    func disconnect() async {
        guard let uid = sharing.uid else { return }
        phase = .working
        await drive.disconnect(uid: uid)
        remote = nil; checkedRemote = false; preview = nil; message = nil; resultMessage = nil
        phase = .idle
    }

    // MARK: バックアップ

    func refresh() async {
        guard isConnected else { return }
        await run { try await self.loadRemote() }
    }

    private func loadRemote() async throws {
        remote = try await client.find()
        checkedRemote = true
    }

    func backupNow() async {
        guard canBackup else { message = tr("デモモードの記録は、バックアップできません。"); return }
        await run { try await self.performBackup() }
    }

    private func performBackup() async throws {
        let document = BackupDocument.make(
            sessions: app.sessions.all(), cards: app.cards.all(), preferences: app.prefs,
            theme: ThemeStore.shared.color.rawValue, language: LanguageStore.shared.language.rawValue)
        let data = try document.encoded()
        // 既存のファイルを確認してから上書きする（重複して作らない）
        let existing = try await client.find()
        remote = try await client.save(data, existing: existing)
        checkedRemote = true
        lastBackupAt = Date()
        resultMessage = tr("バックアップしました。（記録 {0} 件）", "\(document.sessions.count)")
    }

    // MARK: 復元

    /// Driveから取得して、取り込む内容を確認用に作る。端末は、まだ変えない。
    func prepareRestore() async {
        await run {
            guard let file = try await self.client.find() else { throw DriveError.notFound }
            let data = try await self.client.download(file)
            let document: BackupDocument
            do { document = try BackupDocument.parse(data) } catch BackupDocument.ParseError.newerVersion {
                self.message = tr("このバックアップは、新しいバージョンのふとで作られています。アプリを更新してください。"); return
            } catch {
                self.message = tr("バックアップを読み込めませんでした。ファイルが壊れているかもしれません。"); return
            }
            let plan = BackupMergePlan.make(
                document: document,
                existingSessionIDs: Set(self.app.sessions.all().map(\.id)),
                existingCardKeys: Set(self.app.cards.all().map(\.key)))
            self.pendingDocument = document
            self.pendingPlan = plan
            self.preview = RestorePreview(createdAt: document.createdAt, totalSessions: document.sessions.count,
                                          newSessions: plan.newSessions.count, skippedSessions: plan.skippedSessions, newCards: plan.newCards.count)
        }
    }

    func cancelRestore() {
        preview = nil; pendingPlan = nil; pendingDocument = nil
    }

    /// 承認のあとで、取り込む。既存の記録は消さない・上書きしない。
    func confirmRestore(includeSettings: Bool) {
        guard let plan = pendingPlan, let document = pendingDocument else { return }
        guard BackupRestorer.apply(plan, to: app.sessions.context) else {
            message = tr("復元に失敗しました。端末の記録は、変えていません。")
            return
        }
        if includeSettings {
            app.updatePreferences { $0 = document.preferences }
            if let raw = document.theme, let color = ThemeColor(rawValue: raw) { ThemeStore.shared.select(color) }
            if let raw = document.language, let language = AppLanguage(rawValue: raw) { app.changeLanguage(language) }
        }
        app.refresh()
        resultMessage = tr("復元しました。（追加 {0} 件）", "\(plan.newSessions.count)")
        cancelRestore()
    }

    // MARK: 削除

    func deleteRemote() async {
        await run {
            guard let file = try await self.client.find() else { self.remote = nil; return }
            try await self.client.delete(file)
            self.remote = nil
            self.lastBackupAt = nil
            self.resultMessage = tr("Driveのバックアップを削除しました。")
        }
    }

    // MARK: 共通

    private func run(_ work: @escaping () async throws -> Void) async {
        message = nil; resultMessage = nil
        phase = .working
        defer { phase = .idle }
        do { try await work() } catch let error as DriveError {
            message = Self.text(for: error)
            if error == .needsConsent { syncConnection() }
        } catch { message = tr("うまくいきませんでした。もう一度お試しください。") }
    }

    static func text(for error: DriveError) -> String {
        switch error {
        case .notConfigured: return tr("共有の設定がまだ終わっていません。")
        case .cancelled: return ""
        case .needsConsent: return tr("Driveの許可が必要です。もう一度、許可してください。")
        case .offline: return tr("通信できませんでした。つながってから、もう一度お試しください。")
        case .notFound: return tr("Driveに、バックアップが見つかりませんでした。")
        case .quota: return tr("Driveの空き容量が足りません。")
        case .apiDisabled: return tr("Google Drive APIが有効になっていません。設定の手順を確認してください。")
        case .failed: return tr("うまくいきませんでした。もう一度お試しください。")
        }
    }
}
