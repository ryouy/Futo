import SwiftUI
import UIKit

/// 選べるテーマカラー。背景の温かい生成り色は共通で、アクセント色と淡い面の色だけが変わる。
enum ThemeColor: String, CaseIterable, Identifiable {
    case wakaba
    case sora
    case sakura
    case fuji

    var id: String { rawValue }

    var name: String {
        switch self {
        case .wakaba: return tr("深緑")
        case .sora: return tr("空")
        case .sakura: return tr("桜")
        case .fuji: return tr("藤")
        }
    }

    /// (ライト, ダーク)。ライトは生成り色の地に濃いめの差し色。
    /// ダークは、黒に寄せず、やわらかい深緑グレーの地に、少し持ち上げたカードと、パステル調の差し色にして、
    /// 夜でも張りつめない雰囲気にする。
    struct Palette {
        var accent: (UInt32, UInt32)
        var backgroundTop: (UInt32, UInt32)
        var backgroundBottom: (UInt32, UInt32)
        var card: (UInt32, UInt32)
        var soft: (UInt32, UInt32)
    }

    /// 文字や細い線に使うアクセント色。ライトは本体と同じ。ダークは、同じ色相のまま、くすませて明るくした色
    /// （濃い本体の色のままだと、暗い地の上で文字が読めない。蛍光っぽくならないよう、彩度は低く保つ）。
    var textAccent: (UInt32, UInt32) {
        switch self {
        case .wakaba: return (0x196459, 0x86B5A7)
        case .sora: return (0x46789A, 0x8FB2C9)
        case .sakura: return (0xA25A72, 0xD2A3B1)
        case .fuji: return (0x6F5CA3, 0xB1A5D3)
        }
    }

    var palette: Palette {
        switch self {
        case .wakaba:
            return Palette(accent: (0x196459, 0x196459), backgroundTop: (0xFCF8F0, 0x26312E),
                           backgroundBottom: (0xE8F1EE, 0x1F2926), card: (0xFFFEFA, 0x2F3B37), soft: (0xDDEBE7, 0x2B3D39))
        case .sora:
            return Palette(accent: (0x46789A, 0x46789A), backgroundTop: (0xFCF8F0, 0x262D34),
                           backgroundBottom: (0xEAF1F5, 0x1F262D), card: (0xFFFEFA, 0x2F3841), soft: (0xE1EDF4, 0x2B3945))
        case .sakura:
            return Palette(accent: (0xA25A72, 0xA25A72), backgroundTop: (0xFCF8F0, 0x312B2D),
                           backgroundBottom: (0xF7ECEE, 0x282224), card: (0xFFFEFA, 0x3A3235), soft: (0xF5E3E8, 0x3B3034))
        case .fuji:
            return Palette(accent: (0x6F5CA3, 0x6F5CA3), backgroundTop: (0xFCF8F0, 0x2C2B34),
                           backgroundBottom: (0xF0ECF6, 0x24232C), card: (0xFFFEFA, 0x35343F), soft: (0xE8E3F3, 0x363448))
        }
    }
}

/// 現在のテーマ。Observationにより、`Theme` の色を読んでいる画面は、変更時に自動で再描画される。
@Observable
final class ThemeStore {
    static let shared = ThemeStore()
    private static let key = "settings.themeColor"
    private static let customKey = "settings.customThemeHex"

    private(set) var color: ThemeColor
    /// 好きな色（「#RRGGBB」）。選んでいれば、4つのテーマより、こちらが優先される
    private(set) var customHex: String?

    private init() {
        color = ThemeColor(rawValue: UserDefaults.standard.string(forKey: Self.key) ?? "") ?? .wakaba
        let saved = UserDefaults.standard.string(forKey: Self.customKey)
        customHex = saved.flatMap { RGB(hex: $0) != nil ? $0 : nil }
    }

    var isCustom: Bool { customHex != nil }

    /// 画面の再描画の目印（テーマが変わったら、値が変わる）
    var selectionKey: String { customHex ?? color.rawValue }

    func select(_ newColor: ThemeColor) {
        color = newColor
        customHex = nil
        UserDefaults.standard.set(newColor.rawValue, forKey: Self.key)
        UserDefaults.standard.removeObject(forKey: Self.customKey)
    }

    /// 好きな色にする。形式が正しくなければ、何もしない。
    func selectCustom(hex: String) {
        guard let rgb = RGB(hex: hex) else { return }
        customHex = rgb.hex
        UserDefaults.standard.set(rgb.hex, forKey: Self.customKey)
    }

    /// バックアップに入れる値（4つのテーマは名前、好きな色は「custom:#RRGGBB」）
    var backupValue: String { customHex.map { "custom:\($0)" } ?? color.rawValue }

    /// バックアップから戻す。知らない値は、何もしない。
    func restore(backupValue raw: String) {
        if raw.hasPrefix("custom:") { selectCustom(hex: String(raw.dropFirst("custom:".count))) }
        else if let color = ThemeColor(rawValue: raw) { select(color) }
    }

    var palette: ThemeColor.Palette {
        if let customHex, let rgb = RGB(hex: customHex) {
            let c = CustomPalette.colors(for: rgb)
            return ThemeColor.Palette(accent: (c.accent, c.accent), backgroundTop: (c.backgroundTopLight, c.backgroundTopDark),
                                      backgroundBottom: (c.backgroundBottomLight, c.backgroundBottomDark), card: (c.cardLight, c.cardDark), soft: (c.softLight, c.softDark))
        }
        return color.palette
    }

    /// 文字・細い線のアクセント（ライト, ダーク）
    var textAccent: (UInt32, UInt32) {
        if let customHex, let rgb = RGB(hex: customHex) {
            let c = CustomPalette.colors(for: rgb)
            return (c.accent, c.textAccentDark)
        }
        return color.textAccent
    }
}

/// 温かい生成り色と、選んだテーマの落ち着いた色。強い白・黒や原色を避け、ダークモードでも同じ穏やかさを保つ。
enum Theme {
    private static func dynamic(_ pair: (UInt32, UInt32)) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? rgb(pair.1) : rgb(pair.0) })
    }

    private static func rgb(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    private static var palette: ThemeColor.Palette { ThemeStore.shared.palette }

    static var backgroundTop: Color { dynamic(palette.backgroundTop) }
    static var backgroundBottom: Color { dynamic(palette.backgroundBottom) }
    static var card: Color { dynamic(palette.card) }
    static var accent: Color { dynamic(palette.accent) }
    /// 文字・アイコン・細い線のアクセント色（ダークでは、読めるよう少し明るい）
    static var accentText: Color { dynamic(ThemeStore.shared.textAccent) }
    /// アクセント色の上に置く文字色
    static var onAccent: Color { dynamic((0xFFFEFA, 0xEEE9DF)) }
    /// 補足や案内に使う、テーマ色の淡い面。
    static var softBlue: Color { dynamic(palette.soft) }
    /// ほんのり暖かい色。お知らせ用。赤い警告色は使わない。
    static var softPeach: Color { dynamic((0xF8EADF, 0x443A31)) }

    /// 文字の色。ダークでは、真っ白ではなく、やわらかい生成り色。ライトはOS標準のまま。
    static var text: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? rgb(0xEEE9DF) : .label })
    }

    /// 円グラフの色。1つ目はテーマ色、あとは、テーマ色と色相の離れた、はっきり違う色を並べる
    /// （テーマ色の濃淡だけでは、見分けにくいため）。
    static var chartColors: [Color] {
        let pool: [(UInt32, UInt32)] = [
            (0xE0AE4F, 0xD2B887),   // 黄
            (0xD98A63, 0xD09C82),   // 橙
            (0x6FA6C8, 0x88A9BF),   // 空
            (0x7DB48F, 0x8DB89B),   // 若葉
            (0xB9B6AE, 0x8F938E),   // 灰
        ]
        let accent = RGB(palette.accent.0)
        let accentHue = accent.hsb.h
        let usable = pool.filter { entry in
            let hsb = RGB(entry.0).hsb
            if hsb.s < 0.15 { return true }   // 灰は、どのテーマとも区別できる
            let d = abs(hsb.h - accentHue)
            return min(d, 1 - d) > 0.06
        }
        return [accentText] + usable.map { dynamic($0) }
    }

    /// 時間帯グラフの色。朝は黄、昼は空、夕方は橙、夜はテーマ色。
    static func bandColor(_ band: TimeBand) -> Color {
        switch band {
        case .morning: return dynamic((0xE0AE4F, 0xD2B887))
        case .daytime: return dynamic((0x6FA6C8, 0x88A9BF))
        case .evening: return dynamic((0xD98A63, 0xD09C82))
        case .night: return accentText
        }
    }

    static var background: LinearGradient {
        LinearGradient(colors: [backgroundTop, backgroundBottom], startPoint: .top, endPoint: .bottom)
    }
}

struct CardStyle: ViewModifier {
    var tint: Color

    func body(content: Content) -> some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Theme.accent.opacity(0.10), lineWidth: 1)
            )
    }
}

extension View {
    func card(tint: Color? = nil) -> some View { modifier(CardStyle(tint: tint ?? Theme.card)) }
}

/// 主操作・副操作とも、押しやすくやわらかい形のボタン。
struct FutoButtonStyle: ButtonStyle {
    var prominent = true
    /// 白っぽい面に、ごく細い縁だけ（飾らない）。背景の生成り色とは、白さで区別する。
    var bordered = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    private func fill(pressed: Bool) -> Color {
        if !isEnabled { return Color.gray.opacity(0.22) }
        if prominent { return Theme.accent }
        if bordered {
            // 白目の面（ダークでは、カードの色）。押したときだけ、テーマ色の淡い面になる
            let base = colorScheme == .dark ? Theme.card : Color.white
            return pressed ? Theme.softBlue : base
        }
        return Theme.accent.opacity(pressed ? 0.38 : 0.14)
    }

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .font(.headline.weight(.medium))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.horizontal, 16)
            .foregroundStyle(!isEnabled ? Color.secondary : (prominent ? Theme.onAccent : Theme.accentText))
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(fill(pressed: pressed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Theme.accent.opacity(bordered && !prominent && isEnabled ? 0.18 : 0), lineWidth: 1)
            )
            .opacity(isEnabled ? (pressed && prominent ? 0.85 : 1) : 1)
    }
}

/// 行の中に並べる、小さな操作ボタン。押せることが分かるよう、色つきの丸い形にする（削除などは赤）。
struct ChipButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let destructive = configuration.role == .destructive
        let tint: Color = destructive ? .red : Theme.accentText
        configuration.label
            .font(.subheadline.weight(.medium))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: 40)
            .padding(.horizontal, 10)
            .foregroundStyle(tint)
            .background(Capsule().fill(tint.opacity(0.14)))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .contentShape(Capsule())
    }
}

/// 文字列をコピーするアイコン。押すと、少しの間チェックに変わる。
/// 「コピー」（アイコン付き）。押すと、少しの間「コピーしました」になる。ChipButtonStyle の行に並べる用。
struct CopyLabelButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        Button {
            UIPasteboard.general.string = text
            copied = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.6))
                copied = false
            }
        } label: {
            Label(copied ? tr("コピーしました") : tr("コピー"), systemImage: copied ? "checkmark" : "doc.on.doc")
        }
        .buttonStyle(ChipButtonStyle())
    }
}

struct CopyIconButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        Button {
            UIPasteboard.general.string = text
            copied = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.6))
                copied = false
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.body.weight(.medium))
                .foregroundStyle(Theme.accentText)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(copied ? tr("コピーしました") : tr("コピー"))
    }
}

/// 行の中に並べる、コピーのボタン（ChipButtonStyleと並べる用）。押すと、少しの間チェックに変わる。
struct CopyChip: View {
    let text: String
    @State private var copied = false

    var body: some View {
        Button {
            UIPasteboard.general.string = text
            copied = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.6))
                copied = false
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
        }
        .accessibilityLabel(copied ? tr("コピーしました") : tr("コピー"))
    }
}

/// フォームの中で、主な操作を1つだけ大きなボタンにする（背景は透明）。
struct PrimarySection<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Section { content.buttonStyle(FutoButtonStyle()) }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
    }
}

extension AnyTransition {
    /// 古い画面が先に消え、そのあとに新しい画面が現れる。2つが重なって文字が二重に見えるのを避ける。
    static var sequentialFade: AnyTransition {
        .asymmetric(
            insertion: .opacity.animation(.easeOut(duration: 0.3).delay(0.2)),
            removal: .opacity.animation(.easeIn(duration: 0.2)))
    }
}

/// 内容を画面の縦方向の中央に置く。長くなる（文字拡大など）ときはスクロールできる。
struct CenteredScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content
                    .padding(24)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .center)
            }
        }
    }
}

/// 左に名前、右に操作を置く1行。名前の幅を、行の幅から右側の幅を引いた値に固定する。
/// アプリ名のラベルはOSが描画する部品で、親の幅を無視して広がることがあるため、
/// `maxWidth` では押さえきれず、行が画面の外へはみ出す。幅を測って固定し、はみ出しを切り落とす。
struct FixedWidthRow<Leading: View, Trailing: View>: View {
    let height: CGFloat
    let trailingWidth: CGFloat
    var alignment: Alignment = .leading
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                leading
                    .frame(width: max(0, proxy.size.width - trailingWidth), alignment: alignment)
                    .clipped()
                trailing
                    .frame(width: trailingWidth, alignment: .trailing)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
        }
        .frame(height: height)
    }
}

/// 単一・複数選択の1行。目的選択とアプリ選択で共通に使う。
struct ChoiceRow<Content: View>: View {
    let isOn: Bool
    /// 右端のチェックの丸を出すか。1つだけ選ぶ画面では出さず、選んだものの枠だけで示す。
    var showsIndicator = true
    let action: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        Button(action: action) {
            FixedWidthRow(height: 58, trailingWidth: showsIndicator ? 30 : 0, alignment: showsIndicator ? .leading : .center) {
                content
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } trailing: {
                if showsIndicator {
                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(Theme.accentText)
                }
            }
            .padding(.horizontal, 20)
            .contentShape(Rectangle())
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(isOn ? Theme.accent : Theme.accent.opacity(0.10), lineWidth: isOn ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// 開発用など、小さく控えめなボタン。
struct FutoCompactButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.footnote.weight(.medium))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(Theme.accentText)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(Capsule().fill(Theme.accent.opacity(0.12)))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// 目立たせたくない操作用の、文字だけのボタン。
struct FutoTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.accentText)
            .frame(maxWidth: .infinity, minHeight: 44)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// ホームや説明で使う、控えめな葉のしるし。
struct LeafMark: View {
    var size: CGFloat = 22
    var body: some View {
        Image(systemName: "leaf")
            .font(.system(size: size, weight: .regular))
            .foregroundStyle(Theme.accentText)
            .accessibilityHidden(true)
    }
}

extension View {
    /// 1行に収める。入りきらないときは少しだけ縮める（折り返さない）。
    func oneLine(_ minimumScale: CGFloat = 0.7) -> some View {
        lineLimit(1).minimumScaleFactor(minimumScale).truncationMode(.tail)
    }
}

/// 設定のまとまり。行の背景を、アプリのカードの色にそろえる（ダークで標準の灰色が浮かないように）。
struct CardSection<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Section { content }
            .listRowBackground(Theme.card)
    }
}

extension ThemeColor {
    /// このテーマのアクセント色（ライト／ダークで切り替わる）。アイコンの色の選択肢などに使う。
    var swatchColor: Color {
        Color(uiColor: UIColor { trait in
            let hex = trait.userInterfaceStyle == .dark ? palette.accent.1 : palette.accent.0
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

extension Theme {
    /// 画面の下地（ホームの後ろ）の色。シートを開いてホームが小さくなったとき、後ろに見える色に使う。
    static var windowBackgroundUIColor: UIColor {
        UIColor { trait in
            let hex = trait.userInterfaceStyle == .dark ? palette.backgroundBottom.1 : palette.backgroundBottom.0
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
    }
}

/// ウィンドウの背景を、テーマの色にする（シートを開いたとき、小さくなったホームの後ろが黒くならないように）。
struct WindowBackgroundSetter: UIViewRepresentable {
    var color: UIColor

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        DispatchQueue.main.async { view.window?.backgroundColor = color }
    }
}

/// 新しいものがあるしるし（小さな赤い丸）。
struct NewBadge: View {
    var size: CGFloat = 10
    var body: some View {
        Circle().fill(Color.red)
            .frame(width: size, height: size)
            .overlay(Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 1.5))
            .accessibilityLabel(tr("新しい記録があります"))
    }
}

/// テーマカラーを変えるとき、変わる前の画面を重ねておき、ふわっと溶けるように消す（色が、ぱっと切り替わらない）。
enum ThemeCrossfade {
    @MainActor
    static func run(_ change: () -> Void) {
        let window = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first { $0.isKeyWindow }
        guard let window, let snapshot = window.snapshotView(afterScreenUpdates: false) else { change(); return }
        snapshot.isUserInteractionEnabled = false
        window.addSubview(snapshot)
        change()
        let duration = UIAccessibility.isReduceMotionEnabled ? 0.23 : 0.58
        // 新しい色の画面が描かれてから、重ねた画面を溶かす
        UIView.animate(withDuration: duration, delay: 0.06, options: [.curveEaseInOut, .allowUserInteraction]) {
            snapshot.alpha = 0
        } completion: { _ in snapshot.removeFromSuperview() }
    }
}

/// 設定・記録の上のタブ。大きく、丸く、押しやすい形。
struct FutoTabPicker<T: Hashable>: View {
    let items: [T]
    @Binding var selection: T
    let title: (T) -> String
    var badge: (T) -> Bool = { _ in false }
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.self) { item in
                let selected = item == selection
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.spring(duration: 0.4, bounce: 0.22)) { selection = item }
                } label: {
                    Text(title(item))
                        .font(.system(size: 14, weight: selected ? .semibold : .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                        .foregroundStyle(selected ? Theme.onAccent : Theme.text)
                        .padding(.horizontal, 2)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background {
                            // 選んだ印が、タブの間をなめらかに滑って移る
                            if selected { Capsule().fill(Theme.accent).matchedGeometryEffect(id: "pill", in: pill) }
                        }
                        .contentShape(Capsule())
                        .overlay(alignment: .topTrailing) {
                            if badge(item) { NewBadge(size: 9).offset(x: -3, y: 3) }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(5)
        .background(Capsule().fill(Theme.softBlue.opacity(0.5)))
        .animation(.spring(duration: 0.4, bounce: 0.22), value: selection)
    }
}

extension View {
    /// 広い画面（iPad）では、中身を読みやすい幅の中央にまとめる。iPhoneの幅では何も変わらない。
    func readableColumn(_ width: CGFloat = Layout.columnWidth) -> some View {
        frame(maxWidth: width).frame(maxWidth: .infinity)
    }
}

enum Layout {
    /// 広い画面（iPad）で、中身をまとめる最大の幅。横幅いっぱいに広げると間延びするので、読みやすい幅に抑える。広告の幅も、これを超えない。
    static let columnWidth: CGFloat = 640
}

/// 説明の文（カードなし）と、そのすぐ下に置く操作のカード。説明と操作が離れて見えないよう、1つのまとまりにする。
struct DescribedSection<Content: View>: View {
    let lines: [String]
    @ViewBuilder var content: Content

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(lines, id: \.self) { Text($0) }
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 0, trailing: 8))
            content.listRowBackground(Theme.card)
        }
    }
}

/// アプリ内の日付は、すべてスラッシュ区切り（2026/10/31）。時刻は24時間表記。
enum DateText {
    private static func format(_ date: Date, _ pattern: String, locale: Locale = Locale(identifier: "en_US_POSIX")) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    static func day(_ date: Date) -> String { format(date, "yyyy/MM/dd") }
    static func dayTime(_ date: Date) -> String { format(date, "yyyy/MM/dd HH:mm") }
    static func time(_ date: Date) -> String { format(date, "HH:mm") }
    /// 「2026/10/31 土」。曜日は、アプリの言語で。
    static func dayWeekday(_ date: Date, wide: Bool = false) -> String {
        "\(day(date)) \(format(date, wide ? "EEEE" : "EEE", locale: LanguageStore.shared.language.locale))"
    }
}

/// 「Googleで続ける」のボタン。Google の表示の決まりに合わせた、白（ダークでは暗い灰色）の面に、細い縁。
/// 高さ・角の丸みは、ほかのボタンと同じにそろえる。
struct GoogleSignInButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let dark = colorScheme == .dark
        let fill = dark ? Color(red: 0x13 / 255, green: 0x13 / 255, blue: 0x14 / 255) : Color.white
        let border = dark ? Color(red: 0x8E / 255, green: 0x91 / 255, blue: 0x8F / 255) : Color(red: 0x74 / 255, green: 0x77 / 255, blue: 0x75 / 255)
        let text = dark ? Color(red: 0xE3 / 255, green: 0xE3 / 255, blue: 0xE3 / 255) : Color(red: 0x1F / 255, green: 0x1F / 255, blue: 0x1F / 255)
        configuration.label
            .font(.headline.weight(.medium))
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.horizontal, 16)
            .foregroundStyle(text)
            .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(border, lineWidth: 1))
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

/// OSの色の選択（UIColorPickerViewController）を、ボタンから開く。
@MainActor
final class SystemColorPicker: NSObject, UIColorPickerViewControllerDelegate {
    static let shared = SystemColorPicker()
    private var onChange: ((UIColor) -> Void)?

    func present(initial: UIColor, onChange: @escaping (UIColor) -> Void) {
        guard let top = Self.topViewController() else { return }
        self.onChange = onChange
        let picker = UIColorPickerViewController()
        picker.selectedColor = initial
        picker.supportsAlpha = false
        picker.delegate = self
        top.present(picker, animated: true)
    }

    nonisolated func colorPickerViewController(_ viewController: UIColorPickerViewController, didSelect color: UIColor, continuously: Bool) {
        Task { @MainActor in onChange?(color) }
    }

    private static func topViewController() -> UIViewController? {
        var top = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first { $0.isKeyWindow }?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

/// 好きな色を選ぶ丸い印。選ぶまでは虹色で、選んだあとは、その色の丸。押すと、OSの色の選択が開く。
struct CustomColorWell: View {
    let hex: String
    let isSelected: Bool
    var size: CGFloat = 44
    let label: String
    let onPick: (String) -> Void

    private var current: RGB { RGB(hex: hex) ?? RGB(0x196459) }

    var body: some View {
        Button {
            let rgb = current
            SystemColorPicker.shared.present(initial: UIColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)) { color in
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                color.getRed(&r, green: &g, blue: &b, alpha: &a)
                onPick(RGB(r: Double(r), g: Double(g), b: Double(b)).hex)
            }
        } label: {
            Group {
                if isSelected {
                    Circle().fill(Color(red: current.r, green: current.g, blue: current.b))
                } else {
                    Circle().fill(AngularGradient(colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
                }
            }
            .frame(width: size, height: size)
            .overlay(Image(systemName: isSelected ? "checkmark" : "plus").font(.footnote.bold()).foregroundStyle(.white))
            .overlay(Circle().stroke(.primary.opacity(isSelected ? 0.6 : 0), lineWidth: 2).padding(-4))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
