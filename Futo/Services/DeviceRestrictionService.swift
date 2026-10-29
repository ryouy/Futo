import FamilyControls
import Foundation
import ManagedSettings

/// 実機用。個人向けScreen Time認証と、本アプリ専用のManagedSettingsStoreによる制限。
/// 対象はアプリ単位のみ。カテゴリ・Webサイトは保存しない。
@MainActor
final class DeviceRestrictionService: RestrictionService {
    private enum Key {
        static let selection = "device.selection"
        static let intent = "device.intent"
    }

    enum SelectionResult: Equatable {
        case saved
        /// カテゴリやWebサイトが含まれていた。何も保存していない。
        case unsupportedItems
    }

    private let defaults: UserDefaults
    /// 本アプリ専用のストア。他のScreen Time設定やアプリの設定には触れない。
    private let managedStore = ManagedSettingsStore(named: .init("jp.futo.restriction"))

    private(set) var selection: FamilyActivitySelection
    private(set) var permission: PermissionState = .notDetermined

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Key.selection),
           let saved = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            self.selection = saved
        } else {
            self.selection = FamilyActivitySelection()
        }
        refreshPermission()
    }

    var targetCount: Int { selection.applicationTokens.count }
    var intendsRestriction: Bool { defaults.bool(forKey: Key.intent) }

    func refreshPermission() {
        switch AuthorizationCenter.shared.authorizationStatus {
        case .approved: permission = .approved
        case .denied: permission = .denied
        case .notDetermined: permission = .notDetermined
        @unknown default: permission = .notDetermined
        }
    }

    func requestPermission() async -> String? {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            refreshPermission()
            return permission == .approved ? nil : "許可が完了しませんでした。もう一度お試しください。"
        } catch {
            refreshPermission()
            return "許可が完了しませんでした。もう一度お試しください。"
        }
    }

    /// アプリのみの選択を保存する。カテゴリ・Webサイトが含まれる場合は何も保存しない。
    func saveSelection(_ newSelection: FamilyActivitySelection) -> SelectionResult {
        guard newSelection.categoryTokens.isEmpty, newSelection.webDomainTokens.isEmpty else {
            return .unsupportedItems
        }
        selection = newSelection
        if let data = try? JSONEncoder().encode(newSelection) {
            defaults.set(data, forKey: Key.selection)
        }
        if newSelection.applicationTokens.isEmpty {
            defaults.set(false, forKey: Key.intent)
        }
        return .saved
    }

    func start() {
        guard permission == .approved, !selection.applicationTokens.isEmpty else { return }
        managedStore.shield.applications = selection.applicationTokens
        defaults.set(true, forKey: Key.intent)
    }

    @discardableResult
    func stop() -> Bool {
        managedStore.shield.applications = nil
        defaults.set(false, forKey: Key.intent)
        return managedStore.shield.applications == nil
    }

    /// 権限と本アプリのストアを照合する。OS上でシールドが実際に出ているかまでは確認できない。
    func verify() -> RestrictionState {
        guard intendsRestriction else { return .off }
        guard permission == .approved,
              !selection.applicationTokens.isEmpty,
              managedStore.shield.applications == selection.applicationTokens else {
            return .unverifiable
        }
        return .configured
    }
}
