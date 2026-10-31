import SwiftUI

/// 共有リンクのWebページ（`web/` の ShareView）を、そのまま模した表示。
/// 自分が作ったリンクの中身を、相手に見える形で、アプリの中で確かめるために使う。
/// Webは、ライト固定の、生成り色と深い緑。ここも、ダークモードでも、同じ見た目にする。
struct WebShareReplica: View {
    let name: String?
    let stats: StatsSnapshotDTO
    let createdAt: String

    private enum W {
        static let green = Color(red: 0x19 / 255, green: 0x64 / 255, blue: 0x59 / 255)
        static let soft = Color(red: 0xE3 / 255, green: 0xEF / 255, blue: 0xEB / 255)
        static let cream = Color(red: 0xFC / 255, green: 0xF8 / 255, blue: 0xF0 / 255)
        static let ink = Color(red: 0x1D / 255, green: 0x2B / 255, blue: 0x27 / 255)
        static let muted = Color(red: 0x5D / 255, green: 0x6D / 255, blue: 0x68 / 255)
        static let border = green.opacity(0.12)
        static let teal = Color(red: 0x19 / 255, green: 0x64 / 255, blue: 0x59 / 255)
        static let amber = Color(red: 0xE0 / 255, green: 0xB8 / 255, blue: 0x4A / 255)
        static let coral = Color(red: 0xD9 / 255, green: 0x8A / 255, blue: 0x63 / 255)
        static let sky = Color(red: 0x6F / 255, green: 0xA6 / 255, blue: 0xC8 / 255)
        static let stone = Color(red: 0xB9 / 255, green: 0xC9 / 255, blue: 0xC2 / 255)
    }

    private struct Slice: Identifiable { var label: String; var value: Int; var color: Color; var id: String { label } }
    private struct Mini: Identifiable { var title: String; var slices: [Slice]; var id: String { title } }

    private var minis: [Mini] {
        var result: [Mini] = []
        if let c = stats.counts {
            result.append(Mini(title: tr("ひと呼吸の結果"), slices: [
                Slice(label: tr("使いたい"), value: c.wantsToUse, color: W.amber),
                Slice(label: tr("やめておく"), value: c.deferred, color: W.teal),
                Slice(label: tr("途中でやめた"), value: c.interrupted, color: W.stone),
            ]))
        }
        if let p = stats.purposes {
            result.append(Mini(title: tr("使いたかった目的"), slices: [
                Slice(label: tr("連絡"), value: p.contact, color: W.teal),
                Slice(label: tr("調べもの"), value: p.research, color: W.sky),
                Slice(label: tr("気分転換"), value: p.break, color: W.amber),
                Slice(label: tr("なんとなく"), value: p.noReason, color: W.stone),
            ]))
        }
        if let f = stats.feelings {
            result.append(Mini(title: tr("使ったあとの感想"), slices: [
                Slice(label: tr("満足した"), value: f.satisfied, color: W.teal),
                Slice(label: tr("どちらでもない"), value: f.neutral, color: W.stone),
                Slice(label: tr("使いすぎかも"), value: f.wishedLess, color: W.coral),
            ]))
        }
        return result
    }

    // MARK: 日付（Webと同じ：共有時のタイムゾーンで、2026/10/31）

    private func parse(_ iso: String) -> Date? {
        let a = ISO8601DateFormatter(); a.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return a.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    }

    private func text(_ date: Date, time: Bool) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: stats.timezone) ?? .current
        f.dateFormat = time ? "yyyy/MM/dd HH:mm" : "yyyy/MM/dd"
        return f.string(from: date)
    }

    private var rangeText: String {
        guard let start = parse(stats.periodStart), let end = parse(stats.periodEnd) else { return "" }
        return "\(text(start, time: false))〜\(text(end.addingTimeInterval(-1), time: false))"
    }

    // MARK: 本体

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 12) {
                    card {
                        Text(name ?? tr("匿名")).font(.system(size: 20, weight: .semibold)).foregroundStyle(W.green)
                        Text("\(periodLabel(stats.period))（\(rangeText)）").font(.system(size: 14)).foregroundStyle(W.muted)
                    }
                    if !minis.isEmpty { minisCard }
                    if let r = stats.restriction { restrictionCard(r) }
                    if let phrase = stats.phrase { phraseBox(phrase) }
                    if let message = stats.message { phraseBox(message) }
                    if let date = parse(createdAt) {
                        Text("\(text(date, time: true)) \(tr("に共有"))").font(.system(size: 14)).foregroundStyle(W.muted)
                            .frame(maxWidth: .infinity)
                    }
                    Text("\(tr("ふとの紹介を見る")) ・ \(tr("プライバシーポリシー"))").font(.system(size: 13)).foregroundStyle(W.muted)
                        .padding(.top, 8)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
        }
        .background(W.cream.ignoresSafeArea())
        .environment(\.colorScheme, .light)
        .foregroundStyle(W.ink)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image("Logo").resizable().scaledToFit().frame(width: 36).accessibilityHidden(true)
            Text(tr("ふと")).font(.system(size: 20, weight: .semibold)).tracking(1.6).foregroundStyle(W.cream)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(W.green)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) { content() }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(W.border, lineWidth: 1))
    }

    /// 小さなドーナツを、横に並べる（3つまで）。タイトルが2行でも、1行でも、グラフの位置をそろえる。
    private var minisCard: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: min(minis.count, 3))
        return card {
            LazyVGrid(columns: columns, alignment: .center, spacing: 18) {
                ForEach(minis) { mini in miniDonut(mini) }
            }
        }
    }

    private func miniDonut(_ mini: Mini) -> some View {
        let total = mini.slices.reduce(0) { $0 + $1.value }
        return VStack(spacing: 8) {
            Text(mini.title)
                .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(W.green)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .bottom)
            if total > 0 {
                Donut(slices: mini.slices.map { ($0.value, $0.color) }, total: total)
                    .frame(width: 104, height: 104)
                    .accessibilityElement()
                    .accessibilityLabel(mini.title)
                    .accessibilityValue(mini.slices.filter { $0.value > 0 }.map { "\($0.label) \($0.value)" }.joined(separator: ", "))
            }
            VStack(alignment: .leading, spacing: 3) {
                ForEach(mini.slices) { slice in
                    HStack(alignment: .top, spacing: 6) {
                        Circle().fill(slice.color).frame(width: 9, height: 9).padding(.top, 4)
                        Text(slice.label).font(.system(size: 12)).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private struct Donut: View {
        let slices: [(Int, Color)]
        let total: Int

        var body: some View {
            GeometryReader { proxy in
                let size = min(proxy.size.width, proxy.size.height)
                let line = size * 20 / 120
                ZStack {
                    Circle().stroke(W.soft, lineWidth: line)
                    ForEach(Array(arcs.enumerated()), id: \.offset) { _, arc in
                        Circle().trim(from: arc.start, to: arc.end)
                            .stroke(arc.color, style: StrokeStyle(lineWidth: line, lineCap: .butt))
                    }
                }
                .rotationEffect(.degrees(-90))
                .padding(line / 2)
                .frame(width: size, height: size)
            }
        }

        private var arcs: [(start: CGFloat, end: CGFloat, color: Color)] {
            var offset = 0
            var result: [(CGFloat, CGFloat, Color)] = []
            for (value, color) in slices where value > 0 {
                let start = CGFloat(offset) / CGFloat(total)
                offset += value
                result.append((start, CGFloat(offset) / CGFloat(total), color))
            }
            return result
        }
    }

    private func restrictionCard(_ r: RestrictionCounts) -> some View {
        card {
            Text(tr("制限の管理")).font(.system(size: 17, weight: .semibold)).foregroundStyle(W.green).padding(.bottom, 4)
            row(tr("一時停止"), tr("{0}回", "\(r.pauses)"), divider: true)
            row(tr("制限の終了"), tr("{0}回", "\(r.ends)"), divider: false)
        }
    }

    private func row(_ title: String, _ value: String, divider: Bool) -> some View {
        VStack(spacing: 0) {
            HStack { Text(title); Spacer(); Text(value) }.padding(.vertical, 6)
            if divider { Rectangle().fill(W.green.opacity(0.08)).frame(height: 1) }
        }
    }

    private func phraseBox(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 16, weight: .semibold)).foregroundStyle(W.green)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(W.soft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
