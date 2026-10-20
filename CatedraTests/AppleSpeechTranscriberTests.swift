import Testing
import Foundation
import AVFoundation
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

    /// AVFAudio and Speech call these from their own threads; under Swift 6 a main-actor closure would trap there.
    @Test func callbacksRunOffTheMainThread() async {
        let tap = AppleSpeechTranscriber.tapBlock(for: RequestBox())
        let handler = await AppleSpeechTranscriber.resultHandler(for: AppleSpeechTranscriber(), generation: 0)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 64)!
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                tap(buffer, AVAudioTime(sampleTime: 0, atRate: 44_100))
                handler(nil, nil)
                done.resume()
            }
        }
    }
}
