import XCTest
@testable import Futo

final class ReceivedGroupsTests: XCTestCase {
    private func item(_ id: String, key: String?, name: String?, updated: String, avatar: AvatarSpec? = nil) -> ReceivedFriendShare {
        ReceivedFriendShare(id: id, ownerName: name, period: "thisWeek", createdAt: updated, updatedAt: updated, expiresAt: "2099-01-01T00:00:00.000Z", ownerKey: key, ownerAvatar: avatar)
    }

    func testRecordsFromTheSameSenderAreGroupedNewestFirst() {
        let groups = ReceivedGrouping.group([
            item("1", key: "A", name: "アリス", updated: "2027-01-03T00:00:00.000Z"),
            item("2", key: "B", name: "ボブ", updated: "2027-01-05T00:00:00.000Z"),
            item("3", key: "A", name: "アリス", updated: "2027-01-09T00:00:00.000Z"),
        ])
        XCTAssertEqual(groups.map(\.id), ["A", "B"], "いちばん新しい記録がある人が、先")
        XCTAssertEqual(groups[0].items.map(\.id), ["3", "1"], "グループの中も、新しい順")
        XCTAssertEqual(groups[0].name, "アリス")
    }

    func testSameDisplayNameButDifferentSendersStaySeparate() {
        let groups = ReceivedGrouping.group([
            item("1", key: "A", name: "たろう", updated: "2027-01-01T00:00:00.000Z"),
            item("2", key: "B", name: "たろう", updated: "2027-01-02T00:00:00.000Z"),
        ])
        XCTAssertEqual(groups.count, 2, "同じ名前でも、別の人は、別にする")
    }

    func testAnonymousGroupHasNoNameAndKeepsTheAvatarOfNamedOnesOnly() {
        let groups = ReceivedGrouping.group([item("1", key: "ANON", name: nil, updated: "2027-01-01T00:00:00.000Z")])
        XCTAssertNil(groups[0].name)
        XCTAssertNil(groups[0].avatar)
    }

    func testAvatarIsTakenFromAnyItemThatHasOne() {
        let spec = AvatarSpec(symbol: 1, color: 2)
        let groups = ReceivedGrouping.group([
            item("1", key: "A", name: "アリス", updated: "2027-01-02T00:00:00.000Z"),
            item("2", key: "A", name: "アリス", updated: "2027-01-01T00:00:00.000Z", avatar: spec),
        ])
        XCTAssertEqual(groups[0].avatar, spec)
    }

    func testOldServerWithoutKeysFallsBackToTheName() {
        let groups = ReceivedGrouping.group([
            item("1", key: nil, name: "アリス", updated: "2027-01-01T00:00:00.000Z"),
            item("2", key: nil, name: "アリス", updated: "2027-01-02T00:00:00.000Z"),
            item("3", key: nil, name: nil, updated: "2027-01-03T00:00:00.000Z"),
            item("4", key: nil, name: nil, updated: "2027-01-04T00:00:00.000Z"),
        ])
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.map { $0.items.count }.sorted(), [2, 2])
    }
}
