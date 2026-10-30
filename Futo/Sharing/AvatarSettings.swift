import Foundation
import Observation
import SwiftUI

/// 自分のアイコンの設定。この端末の表示だけに使い、サーバーにも、フレンドにも送らない。
/// 初期は、Googleの写真があれば、それを使う。写真を使わないときは、名前の頭文字を、選んだ色の丸に載せる。
@MainActor
@Observable
final class AvatarSettings {
    static let shared = AvatarSettings()

    /// 選べる色（先頭は、ふとの緑）
    static let palette: [UInt32] = [0x196459, 0x2F6FA8, 0x6C5BA8, 0xB5546B, 0xD0802B, 0x6B7F3A, 0x3E8F86, 0x4A4F5C]

    private static let photoKey = "avatar.usesPhoto"
    private static let colorKey = "avatar.colorIndex"
    @ObservationIgnored private let defaults: UserDefaults

    /// Googleの写真を使うか（写真が取れていないときは、設定にかかわらず頭文字になる）
    var usesPhoto: Bool {
        didSet { defaults.set(usesPhoto, forKey: Self.photoKey) }
    }

    /// 頭文字の丸の色。nil は、テーマ色
    var colorIndex: Int? {
        didSet {
            if let colorIndex { defaults.set(colorIndex, forKey: Self.colorKey) } else { defaults.removeObject(forKey: Self.colorKey) }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        usesPhoto = defaults.object(forKey: Self.photoKey) as? Bool ?? true
        let stored = defaults.object(forKey: Self.colorKey) as? Int
        colorIndex = stored.flatMap { Self.palette.indices.contains($0) ? $0 : nil }
    }

    /// 頭文字の丸の色。選んでいなければ `themeColor`（テーマ色）。
    func fill(themeColor: Color) -> Color {
        if let colorIndex, Self.palette.indices.contains(colorIndex) { return Self.color(hex: Self.palette[colorIndex]) }
        return themeColor
    }

    static func color(hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    /// 写真を表示するか。
    func showsPhoto(available: Bool) -> Bool { usesPhoto && available }

    /// ログアウト・アカウント削除のとき、アイコンの設定を初期に戻す。
    func reset() {
        usesPhoto = true
        colorIndex = nil
    }
}
