import Testing
import Foundation
@testable import Core

@Suite("VoiceMemoQualifier")
struct VoiceMemoQualifierTests {
    @Test("Valid .m4a at 2048 bytes returns VoiceMemoEvent")
    func qualifiesValidM4A() {
        let url = URL(fileURLWithPath: "/tmp/recording.m4a")
        let result = VoiceMemoQualifier.qualifies(url: url, fileSize: 2048)
        #expect(result == VoiceMemoEvent(fileURL: url, fileSize: 2048))
    }

    @Test("Exactly 1024 bytes returns nil")
    func rejectsExactlyThreshold() {
        let url = URL(fileURLWithPath: "/tmp/recording.m4a")
        let result = VoiceMemoQualifier.qualifies(url: url, fileSize: 1024)
        #expect(result == nil)
    }

    @Test("512 bytes returns nil")
    func rejectsBelowThreshold() {
        let url = URL(fileURLWithPath: "/tmp/recording.m4a")
        let result = VoiceMemoQualifier.qualifies(url: url, fileSize: 512)
        #expect(result == nil)
    }

    @Test("0 bytes returns nil")
    func rejectsZeroBytes() {
        let url = URL(fileURLWithPath: "/tmp/recording.m4a")
        let result = VoiceMemoQualifier.qualifies(url: url, fileSize: 0)
        #expect(result == nil)
    }

    @Test(".txt file at 2048 bytes returns nil")
    func rejectsTxtExtension() {
        let url = URL(fileURLWithPath: "/tmp/recording.txt")
        let result = VoiceMemoQualifier.qualifies(url: url, fileSize: 2048)
        #expect(result == nil)
    }

    @Test(".jpg file at 2048 bytes returns nil")
    func rejectsJpgExtension() {
        let url = URL(fileURLWithPath: "/tmp/recording.jpg")
        let result = VoiceMemoQualifier.qualifies(url: url, fileSize: 2048)
        #expect(result == nil)
    }

    @Test("iCloud placeholder .memo.m4a.icloud returns nil")
    func rejectsICloudPlaceholderDotMemo() {
        let url = URL(fileURLWithPath: "/tmp/.memo.m4a.icloud")
        let result = VoiceMemoQualifier.qualifies(url: url, fileSize: 2048)
        #expect(result == nil)
    }

    @Test("iCloud placeholder .voice_memo.m4a.icloud returns nil")
    func rejectsICloudPlaceholderDotVoiceMemo() {
        let url = URL(fileURLWithPath: "/tmp/.voice_memo.m4a.icloud")
        let result = VoiceMemoQualifier.qualifies(url: url, fileSize: 2048)
        #expect(result == nil)
    }

    @Test("1025 bytes returns VoiceMemoEvent (just above threshold)")
    func qualifiesJustAboveThreshold() {
        let url = URL(fileURLWithPath: "/tmp/recording.m4a")
        let result = VoiceMemoQualifier.qualifies(url: url, fileSize: 1025)
        #expect(result == VoiceMemoEvent(fileURL: url, fileSize: 1025))
    }

    // MARK: - QTA format support

    @Test("Valid .qta at 2048 bytes returns VoiceMemoEvent")
    func qualifiesValidQTA() {
        let url = URL(fileURLWithPath: "/tmp/recording.qta")
        let result = VoiceMemoQualifier.qualifies(url: url, fileSize: 2048)
        #expect(result == VoiceMemoEvent(fileURL: url, fileSize: 2048))
    }

    @Test("iCloud placeholder .recording.qta.icloud returns nil")
    func rejectsICloudPlaceholderQTA() {
        let url = URL(fileURLWithPath: "/tmp/.recording.qta.icloud")
        let result = VoiceMemoQualifier.qualifies(url: url, fileSize: 2048)
        #expect(result == nil)
    }

    @Test(".qta at 512 bytes returns nil (below threshold)")
    func rejectsQTABelowThreshold() {
        let url = URL(fileURLWithPath: "/tmp/recording.qta")
        let result = VoiceMemoQualifier.qualifies(url: url, fileSize: 512)
        #expect(result == nil)
    }
}
