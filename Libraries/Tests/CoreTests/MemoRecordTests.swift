import Foundation
import Testing

@testable import Core

@Suite("MemoRecord")
struct MemoRecordTests {
    @Test("Round-trip Codable with nil dateProcessed")
    func roundTripCodableNilDateProcessed() throws {
        let url = URL(fileURLWithPath: "/memos/test.m4a")
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let record = MemoRecord(fileURL: url, dateCreated: date, dateProcessed: nil)

        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(MemoRecord.self, from: data)

        #expect(decoded == record)
        #expect(decoded.fileURL == url)
        #expect(decoded.dateCreated == date)
        #expect(decoded.dateProcessed == nil)
    }

    @Test("Round-trip Codable with non-nil dateProcessed")
    func roundTripCodableWithDateProcessed() throws {
        let url = URL(fileURLWithPath: "/memos/test.m4a")
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let processed = Date(timeIntervalSince1970: 1_700_001_000)
        let record = MemoRecord(fileURL: url, dateCreated: created, dateProcessed: processed)

        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(MemoRecord.self, from: data)

        #expect(decoded == record)
        #expect(decoded.dateProcessed == processed)
    }
}
