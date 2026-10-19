import XCTest
import Foundation
import SpaceWorksAPI

final class AccountNetworkingTests: XCTestCase {
    func testGeneratedSignupRecoveryAndEmailVerificationUseExactNativeContract() async throws {
        var paths: [String] = []
        StubProtocol.lock.lock()
        StubProtocol.handler = { request in
            let path = request.url!.path
            paths.append(path)
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            let data = requestBody(request)
            let body = try JSONSerialization.jsonObject(with: data.isEmpty ? Data("{}".utf8) : data) as! [String: String]
            switch path {
            case "/api/v1/auth/member-sign-up":
                XCTAssertEqual(body, ["display_name": "Meera", "email": "meera@example.test", "phone": "", "password": "new password", "website": ""])
                XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            case "/api/v1/auth/forgot-password":
                XCTAssertEqual(body, ["email": "meera@example.test"])
                XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            case "/api/v1/auth/reset-password":
                XCTAssertEqual(body, ["email": "meera@example.test", "code": "123456", "new_password": "new password"])
                XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            case "/api/v1/auth/email-verification/confirm":
                XCTAssertEqual(body, ["code": "123456"])
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer native-access")
            case "/api/v1/auth/email-verification/resend":
                XCTAssertTrue(body.isEmpty)
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer native-access")
            default: XCTFail("Unexpected generated operation")
            }
            return (200, ["Content-Type": "application/json"], Data(#"{"detail":"Check your email."}"#.utf8))
        }
        StubProtocol.lock.unlock()
        let config = DeviceSession.configuration(); config.protocolClasses = [StubProtocol.self]
        let service = SpaceWorksService(origin: try ServerOrigin("https://spaceworks.example"), session: DeviceSession.make(configuration: config),
                                       initialTokens: TokenPair(access: "native-access", refresh: "native-refresh"))
        try await service.createAccount(name: "Meera", email: "meera@example.test", password: "new password", phone: "")
        try await service.requestPasswordReset(email: "meera@example.test")
        try await service.resetPassword(email: "meera@example.test", code: "123456", new: "new password")
        try await service.confirmEmail(code: "123456")
        try await service.resendEmailVerification()
        XCTAssertEqual(Set(paths).count, 5)
        let pair = await service.refresh.current()
        XCTAssertEqual(pair, TokenPair(access: "native-access", refresh: "native-refresh"), "Acknowledgements never replace a native session")
    }
}
