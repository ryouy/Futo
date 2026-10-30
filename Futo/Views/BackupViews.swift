import SwiftUI

/// Google Driveへのバックアップと復元。手動で、必要なときだけ。
@MainActor
struct BackupView: View {
    @Environment(BackupModel.self) private var backup
    @State private var confirmDisconnect = false
    @State private var confirmDeleteRemote = false
    @State private var includeSettings = true

    var body: some View {
        Form {
            if backup.app.mode != .device {
                CardSection { Text(tr("デモモードの記録は、バックアップできません。")).font(.footnote).foregroundStyle(.secondary) }
            }
            explanation
            if backup.isConnected { connected } else { notConnected }
            if let text = backup.message, !text.isEmpty { CardSection { Text(text).font(.footnote).foregroundStyle(.secondary) } }
            if let text = backup.resultMessage { CardSection { Label(text, systemImage: "checkmark.circle").foregroundStyle(Theme.accent) } }
        }
        .compactForm()
        .navigationTitle(tr("バックアップ"))
        .navigationBarTitleDisplayMode(.inline)
        .task { backup.syncConnection(); await backup.refresh() }
        .sheet(isPresented: Binding(get: { backup.preview != nil }, set: { if !$0 { backup.cancelRestore() } })) {
            restoreSheet
        }
        .confirmationDialog(tr("Driveの許可を取り消しますか？ Drive上のバックアップは、そのまま残ります。"), isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button(tr("取り消す"), role: .destructive) { Task { await backup.disconnect() } }
            Button(tr("キャンセル"), role: .cancel) {}
        }
        .confirmationDialog(tr("Drive上のバックアップを削除しますか？ 取り消せません。端末の記録は消えません。"), isPresented: $confirmDeleteRemote, titleVisibility: .visible) {
            Button(tr("削除する"), role: .destructive) { Task { await backup.deleteRemote() } }
            Button(tr("キャンセル"), role: .cancel) {}
        }
    }

    private var explanation: some View {
        CardSection {
            Text(tr("記録と設定を、Google Driveのふと専用の場所に保存します。"))
            Text(tr("制限の対象・通知の許可は含まれません。ログインと同じGoogleアカウントを選んでください。"))
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var notConnected: some View {
        CardSection {
            Button { Task { await backup.connect() } } label: {
                Label(tr("バックアップを有効にする"), systemImage: "icloud.and.arrow.up")
            }
            .buttonStyle(FutoButtonStyle()).disabled(backup.isWorking)
        }
    }

    @ViewBuilder
    private var connected: some View {
        CardSection {
            if let remote = backup.remote, let date = remote.modifiedTime {
                LabeledContent(tr("最後のバックアップ"), value: date.formatted(date: .abbreviated, time: .shortened))
            } else if backup.checkedRemote {
                Text(tr("まだバックアップはありません。")).foregroundStyle(.secondary)
            }
            Button { Task { await backup.backupNow() } } label: {
                Label(tr("今すぐバックアップ"), systemImage: "icloud.and.arrow.up")
            }
            .buttonStyle(FutoButtonStyle()).disabled(backup.isWorking || !backup.canBackup)
            if backup.isWorking { ProgressView() }
        }
        CardSection {
            Button { Task { await backup.prepareRestore() } } label: {
                Label(tr("バックアップから戻す"), systemImage: "icloud.and.arrow.down")
            }
            .buttonStyle(FutoButtonStyle(prominent: false)).disabled(backup.isWorking || backup.remote == nil)
        }
        CardSection {
            Button(role: .destructive) { confirmDeleteRemote = true } label: { Label(tr("Driveのバックアップを削除"), systemImage: "trash") }
                .frame(minHeight: 44).disabled(backup.isWorking || backup.remote == nil)
            Button { confirmDisconnect = true } label: { Label(tr("Driveの許可を取り消す"), systemImage: "xmark.circle") }
                .frame(minHeight: 44).disabled(backup.isWorking)
        }
    }

    private var restoreSheet: some View {
        NavigationStack {
            Form {
                if let p = backup.preview {
                    CardSection {
                        LabeledContent(tr("バックアップの日時"), value: p.createdAt.formatted(date: .abbreviated, time: .shortened))
                        LabeledContent(tr("記録の件数"), value: "\(p.totalSessions)")
                        LabeledContent(tr("追加される記録"), value: "\(p.newSessions)")
                        if p.skippedSessions > 0 { LabeledContent(tr("すでにある記録"), value: "\(p.skippedSessions)") }
                        LabeledContent(tr("追加される振り返り"), value: "\(p.newCards)")
                    }
                    CardSection {
                        Toggle(tr("設定も戻す"), isOn: $includeSettings)
                        Text(tr("いま端末にある記録は、消えません。足りない記録だけが追加されます。"))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    CardSection {
                        Button(tr("戻す")) { backup.confirmRestore(includeSettings: includeSettings) }
                            .buttonStyle(FutoButtonStyle())
                    }
                }
            }
            .compactForm()
            .navigationTitle(tr("バックアップから戻す"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(tr("閉じる")) { backup.cancelRestore() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
