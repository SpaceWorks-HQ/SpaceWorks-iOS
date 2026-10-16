import Foundation
import OpenAPIRuntime

extension SpaceWorksService {
    public func memberBootstrap(slug: String) async throws -> Components.Schemas.TenantBootstrap {
        try await client.api_v1_bootstrap_retrieve(.init(query: .init(slug: slug))).ok.body.json
    }
    public func submitMemberRequest(slug: String, items: [Components.Schemas.RequestItemInput], purpose: String, idempotencyKey: String) async throws -> Components.Schemas.RequestSubmitResponse {
        try await client.api_v1_public_requests_create(.init(path: .init(makerspace_slug: slug),
            headers: .init(Idempotency_hyphen_Key: idempotencyKey),
            body: .json(.init(requested_for: purpose, items: items)))).created.body.json
    }
    public func renewMemberLoan(id: Int, requestID: Int) async throws -> Components.Schemas.LoanRenewal {
        try await client.api_v1_member_makerspaces_loans_renew_create(.init(path: .init(id: requestID, makerspace_id: id))).ok.body.json
    }
    public func bookingAvailability(slug: String, token: String, start: Date, end: Date) async throws -> Components.Schemas.PublicSpaceAvailability {
        try await client.api_v1_public_spaces_availability_retrieve(.init(path: .init(makerspace_slug: slug, public_token: token),
            query: .init(ends_at: end, starts_at: start))).ok.body.json
    }
    public func createMemberBooking(slug: String, token: String, input: Components.Schemas.PublicBookingInput) async throws -> Components.Schemas.PublicBookingResponse {
        try await client.api_v1_public_spaces_book_create(.init(path: .init(makerspace_slug: slug, public_token: token), body: .json(input))).created.body.json
    }
    public func cancelMemberBooking(slug: String, token: String) async throws -> Components.Schemas.MemberBooking {
        try await client.api_v1_public_my_bookings_cancel_create(.init(path: .init(makerspace_slug: slug, public_token: token))).ok.body.json
    }
    public func registerMemberEvent(slug: String, token: String, input: Components.Schemas.PublicEventRegistrationInput) async throws -> Components.Schemas.PublicEventRegistrationResponse {
        try await client.api_v1_public_events_register_create(.init(path: .init(makerspace_slug: slug, public_token: token), body: .json(input))).created.body.json
    }
    public func cancelMemberEvent(id: Int, registration: Int) async throws -> Components.Schemas.MemberRegistrationCancelResponse {
        try await client.api_v1_member_makerspaces_event_registrations_cancel_create(.init(path: .init(id: registration, makerspace_id: id))).ok.body.json
    }
    public func memberEventQR(id: Int, registration: Int) async throws -> Data {
        let body = try await client.api_v1_member_makerspaces_event_registrations_qr_retrieve(.init(path: .init(id: registration, makerspace_id: id))).ok.body.image_svg_plus_xml
        return try await Data(collecting: body, upTo: 512 * 1024)
    }
    public func memberProfile(id: Int) async throws -> Components.Schemas.AccountProfile {
        try await client.api_v1_member_makerspaces_account_profile_retrieve(.init(path: .init(makerspace_id: id))).ok.body.json
    }
    public func updateMemberProfile(id: Int, input: Components.Schemas.PatchedAccountProfile) async throws -> Components.Schemas.AccountProfile {
        try await client.api_v1_member_makerspaces_account_profile_partial_update(.init(path: .init(makerspace_id: id), body: .json(input))).ok.body.json
    }
    public func communicationPreferences(id: Int) async throws -> Components.Schemas.PreferenceResponse {
        try await client.api_v1_notifications_preferences_retrieve(.init(path: .init(makerspace_id: id))).ok.body.json
    }
    public func updateCommunicationPreference(id: Int, input: Components.Schemas.PatchedPreferenceWrite) async throws -> Components.Schemas.PreferenceResponse {
        try await client.api_v1_notifications_preferences_partial_update(.init(path: .init(makerspace_id: id), body: .json(input))).ok.body.json
    }
}
