#if DEBUG
import XCTest
@testable import SpaceWorks

@MainActor final class DemoGuidanceTests: XCTestCase {
    func testMakerspaceRemountPreservesBothDismissedTips() {
        let session = DemoSession()
        let first = session.makeGuidedMemberState(repository: DemoMemberRepository(), makerspaceID: 7)
        first.dismissGuidance(); first.invalidate()
        let second = session.makeGuidedMemberState(repository: DemoMemberRepository(), makerspaceID: 8)
        XCTAssertTrue(second.showGuidance); second.dismissGuidance(); second.invalidate()
        XCTAssertFalse(session.makeGuidedMemberState(repository: DemoMemberRepository(), makerspaceID: 7).showGuidance)
        XCTAssertFalse(session.makeGuidedMemberState(repository: DemoMemberRepository(), makerspaceID: 8).showGuidance)
    }
    func testReplayIsScopedToPersonaMakerspaceAndFeatureVersion() {
        let session = DemoSession()
        let first = session.makeGuidedMemberState(repository: DemoMemberRepository(), makerspaceID: 7)
        first.dismissGuidance()
        session.makeGuidedMemberState(repository: DemoMemberRepository(), makerspaceID: 8).dismissGuidance()
        first.replayGuidance()
        XCTAssertTrue(session.makeGuidedMemberState(repository: DemoMemberRepository(), makerspaceID: 7).showGuidance)
        XCTAssertFalse(session.makeGuidedMemberState(repository: DemoMemberRepository(), makerspaceID: 8).showGuidance)
        XCTAssertTrue(session.makeGuidedMemberState(repository: DemoMemberRepository(), makerspaceID: 8, featureVersion: "member-v2").showGuidance)
        session.role = .staff
        XCTAssertTrue(session.makeGuidedMemberState(repository: DemoMemberRepository(), makerspaceID: 8).showGuidance)
    }
    func testExitResetClearsMemoryAndCannotAlterAnotherDemoSession() {
        let first = DemoSession(), other = DemoSession()
        let retired = first.makeGuidedMemberState(repository: DemoMemberRepository(), makerspaceID: 7)
        retired.dismissGuidance()
        XCTAssertTrue(other.makeGuidedMemberState(repository: DemoMemberRepository(), makerspaceID: 7).showGuidance)
        first.reset()
        retired.dismissGuidance()
        XCTAssertTrue(first.guidanceFlags.isEmpty)
        XCTAssertTrue(first.makeGuidedMemberState(repository: DemoMemberRepository(), makerspaceID: 7).showGuidance)
    }
}
#endif
