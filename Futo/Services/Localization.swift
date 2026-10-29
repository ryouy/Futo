import Foundation
import Observation

/// アプリ内で切り替えられる表示言語。端末の言語設定とは別に、設定の「その他」で選ぶ。
enum AppLanguage: String, CaseIterable, Identifiable {
    case ja
    case en

    var id: String { rawValue }

    /// 切り替えの選択肢は、どちらの言語で表示していても、その言語自身の名前で出す。
    var displayName: String {
        switch self {
        case .ja: return "日本語"
        case .en: return "English"
        }
    }

    /// 日付・時刻の表記に使う。英語は24時間表記にそろえる。
    var locale: Locale {
        switch self {
        case .ja: return Locale(identifier: "ja_JP")
        case .en: return Locale(identifier: "en_GB")
        }
    }
}

/// 現在の表示言語。`tr` を通した文言を読む画面は、言語が変わると自動で再描画される。
@Observable
final class LanguageStore {
    static let shared = LanguageStore()
    private static let key = "settings.language"

    private(set) var language: AppLanguage

    private init() {
        language = AppLanguage(rawValue: UserDefaults.standard.string(forKey: Self.key) ?? "") ?? .ja
    }

    func select(_ newLanguage: AppLanguage) {
        language = newLanguage
        UserDefaults.standard.set(newLanguage.rawValue, forKey: Self.key)
    }

    /// 初回起動のとき、端末の言語が英語なら英語にする（選んだあとは、その選択を優先する）。
    func applySystemDefaultIfUnset() {
        guard UserDefaults.standard.string(forKey: Self.key) == nil else { return }
        if Locale.preferredLanguages.first?.hasPrefix("en") == true { select(.en) }
    }
}

/// 表示する文言。日本語の文言そのものをキーにして、英語のときは対応表から引く。
/// `{0}` `{1}` は、あとから差し込む値の場所（数や時刻など）。対応表に無いときは、日本語のまま出す。
func tr(_ key: String, _ args: String...) -> String {
    var text = key
    if LanguageStore.shared.language == .en, let english = EnglishStrings.table[key] {
        text = english
    }
    for (index, value) in args.enumerated() {
        text = text.replacingOccurrences(of: "{\(index)}", with: value)
    }
    return text
}
