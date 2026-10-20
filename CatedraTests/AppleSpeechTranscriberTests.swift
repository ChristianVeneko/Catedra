import Testing
import Foundation
@testable import Catedra

struct AppleSpeechTranscriberTests {
    @Test func picksTheExactLocaleOrTheClosestSpanish() {
        let supported: Set = ["en_US", "es_ES", "es_MX", "es_US", "es_CL"]
        #expect(AppleSpeechTranscriber.bestLocale(for: "es-CL", supported: supported) == "es_CL")
        #expect(AppleSpeechTranscriber.bestLocale(for: "es-VE", supported: supported) == "es_US")
        #expect(AppleSpeechTranscriber.bestLocale(for: "es-VE", supported: ["es_ES", "en_US"]) == "es_ES")
        #expect(AppleSpeechTranscriber.bestLocale(for: "es", supported: ["es_CO"]) == "es_CO")
        #expect(AppleSpeechTranscriber.bestLocale(for: "es-VE", supported: ["en_US"]) == nil)
    }
}
