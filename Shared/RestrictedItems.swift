import FamilyControls
import Foundation
import ManagedSettings

/// 制限するもの。アプリ・カテゴリ・ウェブサイトの、OSが発行する不透明なトークンの集まり。
/// 名前やbundle IDは取得しない。表示はOS提供のラベルを使う。
struct RestrictedItems: Codable, Equatable {
    var apps: Set<ApplicationToken> = []
    var categories: Set<ActivityCategoryToken> = []
    var webDomains: Set<WebDomainToken> = []

    init() {}

    init(selection: FamilyActivitySelection) {
        apps = selection.applicationTokens
        categories = selection.categoryTokens
        webDomains = selection.webDomainTokens
    }

    var selection: FamilyActivitySelection {
        var result = FamilyActivitySelection()
        result.applicationTokens = apps
        result.categoryTokens = categories
        result.webDomainTokens = webDomains
        return result
    }

    var isEmpty: Bool { apps.isEmpty && categories.isEmpty && webDomains.isEmpty }
    var count: Int { apps.count + categories.count + webDomains.count }

    func subtracting(_ other: RestrictedItems) -> RestrictedItems {
        var result = self
        result.apps.subtract(other.apps)
        result.categories.subtract(other.categories)
        result.webDomains.subtract(other.webDomains)
        return result
    }

    func isSubset(of other: RestrictedItems) -> Bool {
        apps.isSubset(of: other.apps) && categories.isSubset(of: other.categories)
            && webDomains.isSubset(of: other.webDomains)
    }

    func intersection(_ other: RestrictedItems) -> RestrictedItems {
        var result = RestrictedItems()
        result.apps = apps.intersection(other.apps)
        result.categories = categories.intersection(other.categories)
        result.webDomains = webDomains.intersection(other.webDomains)
        return result
    }

    mutating func remove(_ item: RestrictedItem) {
        switch item {
        case .app(let token): apps.remove(token)
        case .category(let token): categories.remove(token)
        case .web(let token): webDomains.remove(token)
        }
    }

    func contains(_ item: RestrictedItem) -> Bool {
        switch item {
        case .app(let token): return apps.contains(token)
        case .category(let token): return categories.contains(token)
        case .web(let token): return webDomains.contains(token)
        }
    }

    /// 表示順を安定させた一覧（アプリ、カテゴリ、ウェブサイトの順）。
    var sortedItems: [RestrictedItem] {
        var result: [RestrictedItem] = []
        let sortedApps: [ApplicationToken] = apps.sorted { $0.hashValue < $1.hashValue }
        for token in sortedApps { result.append(.app(token)) }
        let sortedCategories: [ActivityCategoryToken] = categories.sorted { $0.hashValue < $1.hashValue }
        for token in sortedCategories { result.append(.category(token)) }
        let sortedWebs: [WebDomainToken] = webDomains.sorted { $0.hashValue < $1.hashValue }
        for token in sortedWebs { result.append(.web(token)) }
        return result
    }

    init(items: [RestrictedItem]) {
        for item in items {
            switch item {
            case .app(let token): apps.insert(token)
            case .category(let token): categories.insert(token)
            case .web(let token): webDomains.insert(token)
            }
        }
    }

    /// 履歴に保存したデータから復元する。以前の版はアプリのトークンの配列だけを保存していた。
    static func decode(_ data: Data?) -> RestrictedItems {
        guard let data else { return RestrictedItems() }
        if let items = try? JSONDecoder().decode(RestrictedItems.self, from: data) { return items }
        var legacy = RestrictedItems()
        legacy.apps = (try? JSONDecoder().decode(Set<ApplicationToken>.self, from: data)) ?? []
        return legacy
    }
}

enum RestrictedItem: Hashable, Identifiable {
    case app(ApplicationToken)
    case category(ActivityCategoryToken)
    case web(WebDomainToken)

    var id: Int { hashValue }
}
