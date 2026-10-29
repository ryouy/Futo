import FamilyControls
import ManagedSettings
import SwiftData
import SwiftUI

/// 1件の記録。何が起きたか、目的、解除していた時間、解除したもの（アイコンだけ）、感想を、必要な分だけ出す。
struct SessionRow: View {
    let session: Session
    var showsDate = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(session.resultTitle).font(.headline.weight(.medium))
                Spacer()
                Text(timeText).font(.footnote).foregroundStyle(.secondary)
            }
            Text([session.purposeText, session.unlockDurationText].compactMap { $0 }.joined(separator: tr("　・　")))
                .font(.footnote)
                .foregroundStyle(.secondary)
            if !unlockedItems.isEmpty {
                HStack(spacing: 8) {
                    ForEach(unlockedItems) { item in
                        ItemLabel(item: item).labelStyle(.iconOnly)
                    }
                }
            }
            if let reflection = session.reflection, reflection != .skipped {
                Text(tr("感想：{0}", "\(reflection.label)")).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .frame(minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var timeText: String {
        let locale = LanguageStore.shared.language.locale
        return showsDate
            ? session.startedAt.formatted(Date.FormatStyle().month().day().hour().minute().locale(locale))
            : session.startedAt.formatted(Date.FormatStyle().hour().minute().locale(locale))
    }

    /// 解除したもの（アプリ・カテゴリ・ウェブサイト）。以前の版の保存形式（アプリのみ）も読める。
    var unlockedItems: [RestrictedItem] {
        RestrictedItems.decode(session.temporaryUnlockedApps).sortedItems
    }
}
