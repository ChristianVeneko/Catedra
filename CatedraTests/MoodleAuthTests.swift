import Testing
import Foundation
@testable import Catedra

struct MoodleAuthTests {
    @Test func tokenResponseIsSuccess() {
        let data = Data(#"{"token":"abc123","privatetoken":null}"#.utf8)
        #expect(MoodleAuthResponse.parse(data) == .success)
    }

    @Test func invalidLoginMapsToInvalidCredentials() {
        let data = Data(#"{"error":"Invalid login, please try again","errorcode":"invalidlogin","stacktrace":null}"#.utf8)
        #expect(MoodleAuthResponse.parse(data) == .invalidCredentials)
    }

    @Test func disabledServiceMapsToServiceUnavailable() {
        let data = Data(#"{"error":"Web services must be enabled","errorcode":"enablewsdescription"}"#.utf8)
        #expect(MoodleAuthResponse.parse(data) == .serviceUnavailable)
        let alt = Data(#"{"error":"The requested service (moodle_mobile_app) is not available","errorcode":"servicenotavailable"}"#.utf8)
        #expect(MoodleAuthResponse.parse(alt) == .serviceUnavailable)
    }

    @Test func otherErrorsAreReportedVerbatim() {
        let data = Data(#"{"error":"Account suspended","errorcode":"suspended"}"#.utf8)
        #expect(MoodleAuthResponse.parse(data) == .rejected("Account suspended"))
    }

    @Test func garbageIsAnUnexpectedResponse() {
        #expect(MoodleAuthResponse.parse(Data("<html>".utf8)) == .rejected("Respuesta inesperada de SAIA."))
        #expect(MoodleAuthResponse.parse(Data("{}".utf8)) == .rejected("Respuesta inesperada de SAIA."))
    }

    @Test func requestIsAFormPostWithEncodedFields() throws {
        let request = MoodleAuthRequest.make(username: "ana+1", password: "p&ss=wo rd/é")
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://saia.uft.edu.ve/login/token.php")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        let body = try #require(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        #expect(body == "username=ana%2B1&password=p%26ss%3Dwo%20rd%2F%C3%A9&service=moodle_mobile_app")
    }

    @Test func resultsHaveSpanishMessages() {
        #expect(MoodleAuthResult.success.message.contains("correcta"))
        #expect(MoodleAuthResult.invalidCredentials.message.contains("incorrectos"))
        #expect(MoodleAuthResult.success.isSuccess)
        #expect(!MoodleAuthResult.invalidCredentials.isSuccess)
    }
}
