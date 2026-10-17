#if DEBUG
import Foundation

struct DemoGuidanceKey: Hashable {
    let role: DemoSession.Role
    let makerspaceID: Int
    let featureVersion: String
}

@MainActor extension DemoSession {
    func makeGuidedMemberState(repository: any MemberRepository, makerspaceID: Int, featureVersion: String = "member-v1") -> MemberState {
        let key = DemoGuidanceKey(role: role, makerspaceID: makerspaceID, featureVersion: featureVersion)
        let owner = guidanceEpoch
        return MemberState(repository: repository, initialGuidance: guidanceFlags[key] ?? true, guidanceChanged: { [weak self] visible in
            guard let self, self.guidanceEpoch == owner else { return }
            self.guidanceFlags[key] = visible
        })
    }
}
#endif
