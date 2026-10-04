import Testing
@testable import Catedra

struct ResourceFormatterTests {
    @Test func bytesUseMBBelowAGigabyte() {
        #expect(ResourceFormatter.bytes(0) == "0 MB")
        #expect(ResourceFormatter.bytes(512 * 1_048_576) == "512 MB")
        #expect(ResourceFormatter.bytes(1_048_576 * 12) == "12 MB")
    }
    @Test func bytesUseGBWithTwoDecimals() {
        #expect(ResourceFormatter.bytes(1_073_741_824) == "1.00 GB")
        #expect(ResourceFormatter.bytes(UInt64(2.55 * 1_073_741_824)) == "2.55 GB")
    }
    @Test func smallValuesRoundUpToOneMB() {
        #expect(ResourceFormatter.bytes(1_000) == "0 MB")
        #expect(ResourceFormatter.bytes(700_000) == "1 MB")
    }
    @Test func cpuHasOneDecimal() {
        #expect(ResourceFormatter.cpu(133.46) == "133.5%")
        #expect(ResourceFormatter.cpu(0) == "0.0%")
    }
}
