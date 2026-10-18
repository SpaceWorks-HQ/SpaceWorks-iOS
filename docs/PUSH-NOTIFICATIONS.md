# Native push integration

This phase uses the pinned generated `api_v1_integrations_push_devices_create` (200/201) and
`api_v1_integrations_push_devices_destroy` (204) operations. Create sends exactly token, provider
`apns`, and the signed build's development/production environment. The selected makerspace header
owns each registration; no makerspace ID is invented in the JSON body. Delete404 is already clean.

`PushRegistrationState` owns one server/account. Construct it with
`LivePushRegistrationRepository(service:)`, `PushRegistrationVault(origin:accountID:)`, the actual
build's configured status, and the existing unauthorized/forbidden transitions. Never construct
an enabled live registrar from Demo. The state has no OS permission or SDK calls; the owning
notification UI first explains push and requests native permission only after an explicit action.

- `load()` restores the account-scoped consent and known IDs.
- `enable(token:environment:authorizedDirectMembershipIDs:)` records explicit consent and reconciles
  each current direct membership. Tokens are bounded hexadecimal APNs bytes, not a fixed32-byte rule.
- `synchronize(...)` handles token rotation/foreground/current membership refresh only when consent
  already exists. A matching digest/environment avoids duplicate registration after process restart.
- `disable(authorizedDirectMembershipIDs:)` stores consent off before best-effort server cleanup.
- `pause(authorizedDirectMembershipIDs:)` handles externally revoked OS permission: cleanup
  preserves account consent and the state remains usable for synchronization after permission
  is restored. New token callbacks are blocked while cleanup awaits; throttled requests wait.
- `stop(authorizedDirectMembershipIDs:)` immediately refuses later token callbacks, waits for the
  in-flight serialized transaction, deletes known registrations and invalidates private UI state.
  The auth owner first clears SDK callbacks, the cached OS token and OS registration synchronously
  through `NativeNotifications.reset()`, then awaits this cleanup BEFORE device logout,
  password/security session ending or token removal. Its owner UUID prevents an older async
  cleanup from resetting a newer account/server's SDK callbacks. Logout preserves that account's consent; it does not grant a
  different account permission. Failed server deletes remain pending securely for a later login.
- `removeMembership(_:authorizedDirectMembershipIDs:)` runs BEFORE a voluntary leave while it can
  still authorize that scope. It suspends that maker against a queued old-token callback. If the
  cleanup returns `false`, do not submit the leave mutation: surface the cleanup error or retained
  retry deadline. API mutations honor that deadline; logout's `stop` remains best effort.
  If the leave fails and fresh identity confirms membership remains, `resumeMembership(...)` permits the
  next synchronization. Local resume sends no request and preserves any throttle deadline. A successful leave never resumes it. Authority loss cannot authorize a
  cleanup call; local routing refuses that old maker and its metadata is dropped.

The coordinator explicitly serializes across awaits; actor isolation alone does not. Main-actor
authorization callbacks execute only after the serial lock is released, allowing the auth owner
to await cleanup without deadlock. SDK callbacks never prove server registration. Register
responses must confirm the actual ID/maker/provider/environment/active state before publication.

The device-only, non-synchronizing Keychain stores consent, returned IDs, environment and SHA-256
token digests. No raw APNs token is persisted by this layer. It scopes metadata by normalized server
origin and actual account ID. If a newly returned ID cannot be stored, immediate cleanup is tried
and its pending metadata remains in memory for logout. Offline cleanup cannot be claimed as a
successful server deletion; unregistering the SDK and authorization checks remain necessary.

`SpaceWorksService.withPushMakerspace(_:authorizedDirectMembershipIDs:expectedCredentials:operation:)` must independently
check its current direct membership set, permit only the two generated push operation IDs, and
revalidate scope after refresh. It must not change the UI selection or create a second refresh
coordinator. A caller-provided set is not authority. Ordinary API calls cannot use this background
override. The API tests exercise background registration while retaining the selected maker,
scope escape refusal, unknown membership refusal, both success statuses and delete404.

Native capabilities require the owner's real bundle/team, Push provisioning, APNs provider key,
server topics and supported device-session/payload contract. The owner deferred those inputs.
In `branding/brand.json`, `aps_environment` is either `null` (unconfigured) or `"production"`;
the latter generates development APNs for Debug and production APNs for Release. Optional
`associated_domains` is an explicit list such as `["applinks:members.example.org"]` or
`["webcredentials:members.example.org"]`. Configuring either capability requires the owner's
valid ten-character Apple team ID. The generator preserves these owner settings, and simulator
signing excludes APNs entitlements. The server must separately publish and authorize its real
associated-domain file.
Simulator stubs and Debug fixtures do not prove real APNs delivery or production authorization.
The existing inbox remains available without notification permission or push configuration.

## Payload and links (push v2)

The server sends `{"aps":{"alert":{title,body},"thread-id":"<makerspace_id>"},"data":{…}}`.
`thread-id` groups notifications per makerspace. `data` carries string values `v` ("2"),
`event_id`, `makerspace_id`, `feature`, `event`, member-only `inbox_row_id` and an optional `link`.
A payload without `v` is treated as v1 (makerspace inbox only); flat legacy payloads are still read.
Unknown keys are ignored and the body text is never trusted for display or routing.

`link` follows the backend's `mobile_link_contract.py`: shared-host `/m/{slug}/member`,
`/m/{slug}/member/{tab}` (overview, loans, bookings, events, payments, inbox, account),
`/m/{slug}/member/events/{registration}/ticket`, `/m/{slug}/events/{token}`,
`/m/{slug}/bookings/{token}` and `/m/{slug}/items/{item}`, plus the custom-domain forms without
`/m/{slug}`. The slug must resolve to the payload's makerspace in a fresh `/auth/me`; a custom-domain
path uses the payload's makerspace. Anything else (staff admin, control, API, query strings,
unknown destinations) opens that makerspace's inbox. Universal links on the connected deployment
host use the same parser; inbox rows use it too. A custom-domain universal link cannot be mapped to
a makerspace on its own and is refused.

The payload identifies a makerspace but not its deployment origin. Offline logout can leave an old
server registration, and the OS may later reuse its APNs token. The app reauthorizes and fetches all
content from the current server before navigation. The server publishes no notification categories,
so the app registers none.

The live registration repository captures its owning credential installation epoch when identity is
validated. Queued work cannot register or delete using a replacement account's credentials, even if
the same makerspace is selected. A replaced owner detaches locally and retains its own vault metadata
for future authorized cleanup; it does not clean up through its successor.

Foreground receipt never displays untrusted APNs body text. A validated hint for the currently selected
maker queues a fresh identity check and then refreshes that maker's inbox/unread count. It neither
navigates nor changes makerspace; hints for other makers wait for an explicit tap. Failed identity or
read requests cannot publish cached content as a successful refresh.
