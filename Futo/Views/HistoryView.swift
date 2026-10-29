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
            Text([session.purposeText, session.unlockDurationText].compactMap { $0 }.joined(separator: "　・　"))
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
                Text("感想：\(reflection.label)").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .frame(minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var timeText: String {
        showsDate
            ? session.startedAt.formatted(.dateTime.month().day().hour().minute())
            : session.startedAt.formatted(.dateTime.hour().minute())
    }

    /// 解除したもの（アプリ・カテゴリ・ウェブサイト）。以前の版の保存形式（アプリのみ）も読める。
    var unlockedItems: [RestrictedItem] {
        RestrictedItems.decode(session.temporaryUnlockedApps).sortedItems
    }
}
