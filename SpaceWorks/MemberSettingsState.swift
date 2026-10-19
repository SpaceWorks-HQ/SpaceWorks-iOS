import Foundation
import Observation
import SpaceWorksAPI

@MainActor @Observable
final class ProfileEditorState {
    let repository: any MemberActionsRepository
    var displayName = ""
    var firstName = ""
    var lastName = ""
    var phone = ""
    private(set) var original: Components.Schemas.AccountProfile?
    private(set) var busy = false
    private(set) var loaded = false
    private(set) var error: String?
    private(set) var notice: String?
    private(set) var retryAfter: Date?
    private var active = true
    init(repository: any MemberActionsRepository) { self.repository = repository }
    var dirty: Bool {
        guard let original else { return false }
        return displayName != (original.display_name ?? "") || firstName != (original.first_name ?? "") || lastName != (original.last_name ?? "") || phone != (original.phone ?? "")
    }
    func load(now: Date = Date()) async {
        guard active, !busy, (retryAfter ?? .distantPast) <= now else { return }; busy = true; error = nil; defer { busy = false }
        do { let value = try await repository.profile(); guard active else { return }; original = value; discard(); loaded = true }
        catch { if active { self.error = APIError.display(error); retryAfter = APIError.retryDeadline(error) } }
    }
    func discard() {
        guard let original else { return }
        displayName = original.display_name ?? ""; firstName = original.first_name ?? ""; lastName = original.last_name ?? ""; phone = original.phone ?? ""
        notice = nil; error = nil
    }
    func save(now: Date = Date()) async {
        guard active, !busy, loaded, dirty, (retryAfter ?? .distantPast) <= now else { return }
        guard displayName.count <= 200 else { error = String(localized: "Keep your display name to 200 characters or fewer."); return }
        guard firstName.count <= 150, lastName.count <= 150 else { error = String(localized: "Keep each name to 150 characters or fewer."); return }
        guard phone.count <= 32 else { error = String(localized: "Keep your phone number to 32 characters or fewer."); return }
        busy = true; error = nil; notice = nil; defer { busy = false }
        do {
            let value = try await repository.updateProfile(.init(display_name: displayName, first_name: firstName, last_name: lastName, phone: phone))
            guard active else { return }; original = value; discard(); notice = String(localized: "Profile saved.")
        } catch { if active { self.error = APIError.display(error); retryAfter = APIError.retryDeadline(error) } }
    }
    func invalidate() { active = false; original = nil; displayName = ""; firstName = ""; lastName = ""; phone = ""; error = nil; notice = nil }
}

@MainActor @Observable
final class CommunicationPreferencesState {
    var digestsAllowed = true
    let repository: any MemberActionsRepository
    private(set) var cells: [Components.Schemas.PreferenceCell] = []
    private(set) var loaded = false
    private(set) var busy = false
    private(set) var error: String?
    private(set) var retryAfter: Date?
    private var active = true
    init(repository: any MemberActionsRepository) { self.repository = repository }
    func load(now: Date = Date()) async {
        guard active, !busy, (retryAfter ?? .distantPast) <= now else { return }; busy = true; error = nil; defer { busy = false }
        do { let value = try await repository.preferences(); guard active else { return }; cells = value.cells; loaded = true }
        catch { if active { self.error = APIError.display(error); retryAfter = APIError.retryDeadline(error) } }
    }
    func set(_ cell: Components.Schemas.PreferenceCell, enabled: Bool, now: Date = Date()) async {
        guard active, !busy, (retryAfter ?? .distantPast) <= now else { return }
        guard cells.contains(where: { $0.feature == cell.feature && $0.channel == cell.channel && $0.enabled == cell.enabled }) else { return }
        guard !enabled || cell.available else { error = String(localized: "This notification option isn't available in your makerspace."); return }
        await write(.init(feature: cell.feature, channel: cell.channel, enabled: enabled))
    }
    func digest(_ cell: Components.Schemas.PreferenceCell, enabled: Bool, now: Date = Date()) async {
        guard active, !busy, digestsAllowed, cell.available, cell.enabled, cell.channel.rawValue == "email", cell.daily_digest != nil,
              (retryAfter ?? .distantPast) <= now else { return }
        await write(.init(feature: cell.feature, channel: cell.channel, enabled: cell.enabled, daily_digest: enabled))
    }
    private func write(_ input: Components.Schemas.PatchedPreferenceWrite) async {
        busy = true; error = nil; defer { busy = false }
        do { let value = try await repository.updatePreference(input); guard active else { return }; cells = value.cells }
        catch { if active { self.error = APIError.display(error); retryAfter = APIError.retryDeadline(error) } }
    }
    func invalidate() { active = false; cells = []; loaded = false; error = nil }
}
