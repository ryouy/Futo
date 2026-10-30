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

    /// 選べるアイコン（山・海・魚など12個）。名前は、読み上げ用。
    static let symbols: [(name: String, label: String)] = [
        ("mountain.2.fill", "山"), ("water.waves", "海"), ("fish.fill", "魚"), ("leaf.fill", "葉"),
        ("sun.max.fill", "太陽"), ("moon.stars.fill", "月"), ("flame.fill", "炎"), ("snowflake", "雪"),
        ("tortoise.fill", "亀"), ("bird.fill", "鳥"), ("sailboat.fill", "ヨット"), ("pawprint.fill", "足あと"),
    ]

    private static let photoKey = "avatar.usesPhoto"
    private static let colorKey = "avatar.colorIndex"
    private static let symbolKey = "avatar.symbolIndex"
    @ObservationIgnored private let defaults: UserDefaults

    /// Googleの写真を使うか（写真が取れていないときは、設定にかかわらず頭文字になる）
    var usesPhoto: Bool {
        didSet { defaults.set(usesPhoto, forKey: Self.photoKey) }
    }

    /// 選んだアイコン（`symbols` の番号）。nil は、頭文字
    var symbolIndex: Int? {
        didSet {
            if let symbolIndex { defaults.set(symbolIndex, forKey: Self.symbolKey) } else { defaults.removeObject(forKey: Self.symbolKey) }
        }
    }

    /// 頭文字・アイコンの丸の色。nil は、テーマ色
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
        let symbol = defaults.object(forKey: Self.symbolKey) as? Int
        symbolIndex = symbol.flatMap { Self.symbols.indices.contains($0) ? $0 : nil }
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
    func showsPhoto(available: Bool) -> Bool { usesPhoto && symbolIndex == nil && available }

    func selectPhoto() { symbolIndex = nil; usesPhoto = true }
    func selectInitial() { symbolIndex = nil; usesPhoto = false }
    func selectSymbol(_ index: Int) {
        guard Self.symbols.indices.contains(index) else { return }
        symbolIndex = index
        usesPhoto = false
    }

    /// ログアウト・アカウント削除のとき、アイコンの設定を初期に戻す。
    func reset() {
        usesPhoto = true
        colorIndex = nil
        symbolIndex = nil
    }
}

/// 最後に確認した表示名の控え（この端末だけ）。アプリを開いた直後、サーバーの応答を待たずに、自分のアイコンを出すために使う。
enum ProfileCache {
    private static func key(_ uid: String) -> String { "profile.name.\(uid)" }

    static func name(uid: String, defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: key(uid)).flatMap { $0.isEmpty ? nil : $0 }
    }

    static func save(name: String, uid: String, defaults: UserDefaults = .standard) {
        defaults.set(name, forKey: key(uid))
    }

    static func clear(uid: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key(uid))
    }
}
