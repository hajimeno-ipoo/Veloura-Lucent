import Foundation
import Testing
@testable import VelouraLucent

struct ProcessingLogJSONExportTests {
    @Test(arguments: ["standard", "stem"])
    func exportsEveryDisplayedLineInSectionOrder(mode: String) throws {
        let sectionIDs = mode == "stem"
            ? ["correction", "remix", "mastering"]
            : ["correction", "mastering"]
        let sections = sectionIDs.map { id in
            ProcessingLogSection(
                id: id,
                title: "\(id)ログ",
                lines: ["開始: \(id)", "詳細 / \"日本語\"", "完了: \(id)"],
                placeholder: "空の時だけ表示"
            )
        }
        let timestamp = Date(timeIntervalSince1970: 0)

        let data = try ProcessingLogJSONExport.data(mode: mode, sections: sections, exportedAt: timestamp)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let exportedSections = try #require(json["sections"] as? [[String: Any]])

        #expect(json["mode"] as? String == mode)
        #expect(json["exportedAt"] as? String == "1970-01-01T00:00:00Z")
        #expect(exportedSections.compactMap { $0["id"] as? String } == sectionIDs)
        for (source, exported) in zip(sections, exportedSections) {
            #expect(exported["title"] as? String == source.title)
            #expect(exported["lines"] as? [String] == source.lines)
            #expect(exported["placeholder"] == nil)
        }
    }
}
