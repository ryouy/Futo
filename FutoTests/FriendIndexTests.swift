import XCTest
@testable import Futo

final class FriendIndexTests: XCTestCase {
    func testKeysForLatinKanaAndOthers() {
        XCTAssertEqual(FriendIndex.key(for: "ryouy"), "R")
        XCTAssertEqual(FriendIndex.key(for: "Ａｌｉｃｅ"), "A", "全角も、英字として扱う")
        XCTAssertEqual(FriendIndex.key(for: "あきこ"), "あ")
        XCTAssertEqual(FriendIndex.key(for: "ガク"), "か", "カタカナは、ひらがなの行へ。濁点も、同じ行")
        XCTAssertEqual(FriendIndex.key(for: "ぱん"), "は")
        XCTAssertEqual(FriendIndex.key(for: "をん"), "わ")
        XCTAssertEqual(FriendIndex.key(for: "山田"), FriendIndex.other, "漢字は読みが分からないので、他")
        XCTAssertEqual(FriendIndex.key(for: "123"), FriendIndex.other)
        XCTAssertEqual(FriendIndex.key(for: "   "), FriendIndex.other)
    }

    func testSectionOrderIsLatinThenKanaThenOthers() {
        let names = ["山田", "さとう", "bob", "Alice", "あべ", "ケン"]
        let keys = FriendIndex.grouped(names, name: { $0 }).map(\.key)
        XCTAssertEqual(keys, ["A", "B", "あ", "か", "さ", "他"])
    }

    func testItemsInASectionAreSortedByName() {
        let groups = FriendIndex.grouped(["bob", "Bill", "Ben"], name: { $0 })
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].items, ["Ben", "Bill", "bob"])
    }

    func testSearchIgnoresCaseWidthAndKana() {
        let names = ["Alice", "ボブ", "ぼぶ子", "山田"]
        XCTAssertEqual(FriendIndex.filter(names, query: "ali", name: { $0 }), ["Alice"])
        XCTAssertEqual(FriendIndex.filter(names, query: "ＡＬＩ", name: { $0 }), ["Alice"])
        XCTAssertEqual(FriendIndex.filter(names, query: "ぼぶ", name: { $0 }), ["ボブ", "ぼぶ子"], "ひらがなで、カタカナの名前も探せる")
        XCTAssertEqual(FriendIndex.filter(names, query: "山", name: { $0 }), ["山田"])
        XCTAssertEqual(FriendIndex.filter(names, query: "  ", name: { $0 }), names, "空の検索は、すべて")
        XCTAssertTrue(FriendIndex.filter(names, query: "zzz", name: { $0 }).isEmpty)
    }
}
