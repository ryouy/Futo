import XCTest
@testable import Futo

final class LocalizationTests: XCTestCase {
    override func tearDown() {
        LanguageStore.shared.select(.ja)   // 他のテストは日本語を前提にしている
    }

    // MARK: ソースと対応表の整合

    private func sourceFiles() throws -> [URL] {
        let here = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
        let sources = here.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Futo")
        guard let walker = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil) else {
            throw XCTSkip("ソースが見つからない環境（実機・シミュレーターのテスト）では確認しない")
        }
        let files = (walker.allObjects as? [URL] ?? []).filter { $0.pathExtension == "swift" }
        if files.isEmpty { throw XCTSkip("ソースが見つからない環境では確認しない") }
        return files.filter { !$0.lastPathComponent.hasSuffix("EnglishStrings.swift") }
    }

    /// `tr("…")` の最初の引数（日本語の文言）を集める。
    private func usedKeys() throws -> Set<String> {
        var keys = Set<String>()
        let regex = try NSRegularExpression(pattern: #"tr\("((?:[^"\\]|\\.)*)""#)
        for file in try sourceFiles() {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let range = Range(match.range(at: 1), in: text) {
                    // ソース上の `\n` を、実際の改行に直す（実行時のキーと同じにする）
                    keys.insert(String(text[range]).replacingOccurrences(of: "\\n", with: "\n"))
                }
            }
        }
        // `tr(変数)` で渡されるもの
        keys.formUnion(OutingMessages.rawMessages)
        keys.formUnion(DemoRestrictionService.fictionalApps)
        return keys
    }

    func testEveryUsedKeyHasAnEnglishTranslation() throws {
        let missing = try usedKeys().filter { EnglishStrings.table[$0] == nil }.sorted()
        XCTAssertTrue(missing.isEmpty, "英訳が無い文言:\n" + missing.joined(separator: "\n"))
    }

    func testNoUnusedEnglishEntries() throws {
        let used = try usedKeys()
        let unused = EnglishStrings.table.keys.filter { !used.contains($0) }.sorted()
        XCTAssertTrue(unused.isEmpty, "使われていない英訳:\n" + unused.joined(separator: "\n"))
    }

    func testPlaceholdersMatchBetweenLanguages() {
        func slots(_ s: String) -> [String] {
            (0..<6).map { "{\($0)}" }.filter { s.contains($0) }
        }
        for (key, english) in EnglishStrings.table {
            XCTAssertEqual(slots(key), slots(english), "差し込み位置が合わない: \(key)")
            XCTAssertFalse(english.isEmpty, key)
        }
    }

    // MARK: 切り替えの動作

    func testLanguageSwitchChangesOutputAndFallsBackToJapanese() {
        LanguageStore.shared.select(.ja)
        XCTAssertEqual(tr("{0}分", "3"), "3分")
        LanguageStore.shared.select(.en)
        XCTAssertEqual(tr("{0}分", "3"), "3 min")
        XCTAssertEqual(tr("存在しない文言です"), "存在しない文言です", "対応表に無いときは、日本語のまま出す")
        XCTAssertEqual(AppLanguage.allCases.map(\.displayName), ["日本語", "English"], "選択肢は、どちらの言語でも同じ名前")
    }

    func testDurationAndLabelsInEnglish() {
        LanguageStore.shared.select(.en)
        XCTAssertEqual(durationText(seconds: 180), "3 min")
        XCTAssertEqual(durationText(seconds: 10), "10 sec")
        XCTAssertEqual(durationText(seconds: 90), "1 min 30 sec")
        XCTAssertEqual(SessionOutcome.deferred.label, "Not now")
        XCTAssertEqual(Purpose.research.label, "Looking things up")
        XCTAssertEqual(Reflection.wishedLess.label, "Maybe too much")
        XCTAssertEqual(ReflectionKind.morning.title, "Morning review")
    }

    @MainActor
    func testMorningReflectionStartsWithYesterdayInEnglish() throws {
        LanguageStore.shared.select(.en)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let day = LogicalCalendar(calendar: calendar).dayInterval(containing: Date())
        let empty = ReflectionBuilder.build(kind: .morning, sessions: [], mode: .demo, interval: day, dayWord: tr("昨日"))
        XCTAssertEqual(empty.lines.first, "Yesterday, there are no records yet.")
        XCTAssertEqual(empty.title, "Morning review")
    }

    func testOutingMessagesTranslateOneToOne() {
        LanguageStore.shared.select(.en)
        let english = OutingMessages.all
        XCTAssertEqual(english.count, OutingMessages.rawMessages.count)
        XCTAssertEqual(Set(english).count, english.count, "英語でも重複しない")
        // 同じ予定なら、言語が違っても同じ番号の文言が選ばれる
        LanguageStore.shared.select(.ja)
        let ja = OutingMessages.pick(seed: "futo.outing.2027-01-13")
        let index = OutingMessages.all.firstIndex(of: ja)
        LanguageStore.shared.select(.en)
        XCTAssertEqual(OutingMessages.all.firstIndex(of: OutingMessages.pick(seed: "futo.outing.2027-01-13")), index)
    }
}
