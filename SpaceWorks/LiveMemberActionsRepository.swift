import Foundation
import SpaceWorksAPI

struct LiveMemberActionsRepository: MemberActionsRepository {
    let service: SpaceWorksService
    let expectedCredentials: CredentialSnapshot?
    let id: Int
    let slug: String
    var onUnauthorized: @Sendable (String) async -> Void = { _ in }
    var onForbidden: @Sendable () async -> Void = {}
    private func checked<T: Sendable>(_ work: @Sendable () async throws -> T) async throws -> T {
        guard let expectedCredentials, await service.refresh.isSameInstallation(expectedCredentials) else { throw CancellationError() }
        do { return try await service.withMakerspace(id, expectedCredentials: expectedCredentials, operation: work) }
        catch {
            if Task.isCancelled || APIError.isCancellation(error) { throw error }
            guard await service.refresh.isSameInstallation(expectedCredentials) else { throw CancellationError() }
            let empty = await service.refresh.current() == nil
            if APIError.status(error) == 401 || empty { await onUnauthorized(APIError.display(error)) }
            else if APIError.status(error) == 403 { await onForbidden() }
            throw error
        }
    }
    func bootstrap() async throws -> Components.Schemas.TenantBootstrap { try await checked { try await service.memberBootstrap(slug: slug) } }
    func submit(items: [Components.Schemas.RequestItemInput], purpose: String, key: String) async throws -> Components.Schemas.RequestSubmitResponse {
        try await checked { try await service.submitMemberRequest(slug: slug, items: items, purpose: purpose, idempotencyKey: key) }
    }
    func renew(request: Int) async throws -> Components.Schemas.LoanRenewal {
        try await checked { try await service.renewMemberLoan(id: id, requestID: request) }
    }
    func availability(space: String, start: Date, end: Date) async throws -> Components.Schemas.PublicSpaceAvailability {
        try await checked { try await service.bookingAvailability(slug: slug, token: space, start: start, end: end) }
    }
    func book(space: String, input: Components.Schemas.PublicBookingInput) async throws -> Components.Schemas.PublicBookingResponse {
        try await checked { try await service.createMemberBooking(slug: slug, token: space, input: input) }
    }
    func cancelBooking(token: String) async throws -> Components.Schemas.MemberBooking {
        try await checked { try await service.cancelMemberBooking(slug: slug, token: token) }
    }
    func register(event: String, input: Components.Schemas.PublicEventRegistrationInput) async throws -> Components.Schemas.PublicEventRegistrationResponse {
        try await checked { try await service.registerMemberEvent(slug: slug, token: event, input: input) }
    }
    func cancelEvent(registration: Int) async throws -> Components.Schemas.MemberRegistrationCancelResponse {
        try await checked { try await service.cancelMemberEvent(id: id, registration: registration) }
    }
    func eventQR(registration: Int) async throws -> Data {
        try await checked { try await service.memberEventQR(id: id, registration: registration) }
    }
    func profile() async throws -> Components.Schemas.AccountProfile { try await checked { try await service.memberProfile(id: id) } }
    func updateProfile(_ input: Components.Schemas.PatchedAccountProfile) async throws -> Components.Schemas.AccountProfile {
        try await checked { try await service.updateMemberProfile(id: id, input: input) }
    }
    func preferences() async throws -> Components.Schemas.PreferenceResponse { try await checked { try await service.communicationPreferences(id: id) } }
    func updatePreference(_ input: Components.Schemas.PatchedPreferenceWrite) async throws -> Components.Schemas.PreferenceResponse {
        try await checked { try await service.updateCommunicationPreference(id: id, input: input) }
    }
}
