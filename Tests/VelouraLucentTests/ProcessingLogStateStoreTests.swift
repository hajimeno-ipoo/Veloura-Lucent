import Testing
@testable import VelouraLucent

struct ProcessingLogStateStoreTests {
    @Test
    func appendingLinesKeepsFullText() {
        var store = ProcessingLogStateStore()

        store.append("1行目")
        store.append("2行目")

        #expect(store.lines == ["1行目", "2行目"])
        #expect(store.text == "1行目\n2行目")
    }

    @Test
    func visibleLinesKeepOnlyRecentLines() {
        var store = ProcessingLogStateStore()
        let totalLines = ProcessingLogStateStore.visibleLineLimit + 4

        for index in 1 ... totalLines {
            store.append("ログ\(index)")
        }

        #expect(store.lines.count == totalLines)
        #expect(store.visibleLines.count == ProcessingLogStateStore.visibleLineLimit)
        #expect(store.visibleLines.first == "ログ5")
        #expect(store.visibleLines.last == "ログ\(totalLines)")
    }

    @Test
    func resetClearsLinesAndText() {
        var store = ProcessingLogStateStore()
        store.append("古いログ")

        store.reset()

        #expect(store.lines.isEmpty)
        #expect(store.text.isEmpty)
        #expect(store.visibleLines.isEmpty)
    }
}
