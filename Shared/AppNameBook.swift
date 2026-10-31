import Foundation

/// 制限されたものの名前の控え。名前は、OSが「シールド」を出す拡張の中でしか読めない（本体からはトークンしか見えない）。
/// そこで、シールドの拡張が、出したときに名前を書き留め、本体が共有のときに読む。名前は、この端末の中だけに置く。
enum AppNameBook {
    private static let defaultsKey = "device.itemNames.shield"

    /// 本体は "group.<bundle id>"、拡張は末尾を除いた同じ値。
    static var groupID: String {
        var id = Bundle.main.bundleIdentifier ?? ""
        for suffix in [".shieldaction", ".shield", ".monitor"] where id.hasSuffix(suffix) {
            id.removeLast(suffix.count)
        }
        return "group." + id
    }

    private static var defaults: UserDefaults? { UserDefaults(suiteName: groupID) }

    static func key<T: Encodable>(_ token: T) -> String? {
        (try? JSONEncoder().encode(token)).map { $0.base64EncodedString() }
    }

    static func save<T: Encodable>(name: String?, for token: T?) {
        guard let name, !name.isEmpty, let token, let k = key(token), let defaults else { return }
        var names = defaults.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
        guard names[k] != name else { return }
        names[k] = name
        defaults.set(names, forKey: defaultsKey)
    }

    static func name<T: Encodable>(for token: T) -> String? {
        guard let k = key(token), let names = defaults?.dictionary(forKey: defaultsKey) as? [String: String] else { return nil }
        return names[k]
    }
}
