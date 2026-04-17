# JobWin iOS Architecture

Last updated: 2026-04-17

## Architectural Goal

The iOS app should be a native client over the JobWin mobile BFF. It should not duplicate web backend business logic and should not talk directly to Supabase tables.

Responsibilities:

- iOS owns native interaction, local state, routing, device capabilities, and presentation.
- The mobile BFF owns auth context, permissions, data shaping, mutations, and server-side integration logic.
- The web app remains the admin and full-system surface.

## Runtime Host

Primary production host:

```text
https://app.jobwin.io
```

Current auth transport:

```text
Authorization: Bearer <Supabase access token>
```

Current developer auth screen accepts API base URL and Supabase access token. V1 should replace token paste with normal mobile sign-in.

## Project Structure

```text
JobWin/
  App/          app composition, route coordination, scene phase hooks
  Core/         auth, networking, DTOs, formatting, design tokens
  Features/     SwiftUI screens by product area
  Services/     activity, estimate drafts, location, push, app-wide state
```

## Layer Responsibilities

### `App`

Owns environment creation, session restoration, auth gate, tab shell, deep links, and scene phase coordination.

### `Core`

Owns cross-feature primitives: keychain/session storage, API client, shared DTOs, formatting, routing helpers, and design tokens.

### `Features`

Owns native screens and user interactions. One feature folder should map to one product area. Shared UI belongs in `Features/Shared`.

### `Services`

Owns app-wide stateful services: activity cache, shell badges, estimate draft local persistence, location sharing, and push registration.

## Networking

All API calls should go through:

```text
JobWin/Core/Networking/APIClient.swift
JobWin/Core/Networking/MobileAPI.swift
```

Rules:

- add mobile paths to `MobileAPI`
- use `APIClient` for request construction
- prefer typed request/response DTOs in `MobileModels.swift`
- keep raw URL strings out of feature views
- surface backend errors without wiping local user data

## Mobile BFF Contract

The app depends on these endpoint groups:

- `POST /api/mobile/v1/session`
- `GET /api/mobile/v1/bootstrap`
- `GET /api/mobile/v1/activity`
- `POST /api/mobile/v1/activity`
- `GET /api/mobile/v1/home`
- `GET /api/mobile/v1/calendar`
- `GET /api/mobile/v1/jobs`
- `GET /api/mobile/v1/jobs/:jobId`
- job field mutations
- job reschedule
- `GET /api/mobile/v1/clients`
- `GET /api/mobile/v1/clients/:clientId`
- client note mutation
- `GET /api/mobile/v1/tasks`
- task complete mutation
- `GET /api/mobile/v1/inbox/threads`
- `GET /api/mobile/v1/inbox/threads/:threadId`
- inbox note mutation
- `POST /api/mobile/v1/location`
- `DELETE /api/mobile/v1/location`
- `GET /api/mobile/v1/location/technicians`
- `POST /api/mobile/v1/push/register`
- `GET /api/mobile/v1/estimate-drafts`
- `POST /api/mobile/v1/estimate-drafts`

Add new backend needs to the BFF first. Do not bypass it from iOS.

## Auth And Session

Current state:

- `SessionStore` stores base URL in `UserDefaults`
- access token is stored in Keychain
- session refresh validates against `/api/mobile/v1/session`
- `401` or `403` clears the token

Target state:

- user-facing email/password sign in
- password reset or web fallback
- session refresh on app launch
- clear expired session messaging
- no developer-only token paste for normal users

## Permission And Gating Model

The backend is the final authority, but iOS must not expose actions that the user cannot perform.

Rules:

- derive UI actions from bootstrap capabilities and mobile role
- route gating must match visible buttons
- limited-role users should not see CTAs that route to blocked areas
- call/ring-out actions require the same capability used by the backend
- activity center actions must be filtered before rendering

When adding an action:

1. confirm backend capability
2. expose capability in bootstrap if needed
3. hide or downgrade UI when unavailable
4. keep router behavior aligned
5. keep backend enforcement in place

## Routing

Route ownership:

- `AppNavigation.swift` owns route parsing and permission checks
- native screens own feature-specific navigation
- unsupported web surfaces use `SafariSheetView`

Current route families:

- home
- calendar
- tasks and task detail
- jobs and job detail
- inbox and thread detail
- clients and client detail
- estimate and invoice web fallback

Deep links should be deterministic and safe:

```text
jobwin://home
jobwin://calendar
jobwin://jobs
jobwin://job/<id>
jobwin://clients
jobwin://client/<id>
jobwin://inbox
jobwin://thread/<id>
jobwin://tasks
jobwin://task/<id>
```

## Local Persistence

Use local persistence when user input would be expensive or impossible to recreate.

Mandatory local persistence:

- estimate drafts
- captured photos
- captured videos
- voice notes
- upload status
- retryable error state

Rules:

- write local draft state before remote upload
- never block local save on missing client or order
- keep successful media if another file upload fails
- restore drafts after app restart
- keep local state scoped by workspace and user
- distinguish local save status from server upload status

Current implementation starts in:

```text
JobWin/Services/EstimateDrafts/EstimateDraftStore.swift
```

## AI Estimate From Media Architecture

Desired flow:

1. create local draft
2. optionally bind client and order
3. add notes
4. capture photos, short video, and voice
5. persist local files and metadata
6. create or sync remote draft
7. upload media per file with retry
8. trigger backend AI analysis
9. render structured review result
10. allow human edits
11. convert approved draft to estimate

The AI review screen must render separate work item rows, quantity or unit when available, time range, price range, assumptions, missing inputs, confidence warnings, and follow-up questions.

Do not collapse multiple work types into one quantity.

## Camera, Video, And Voice

Platform capability rules:

- camera permission is required for new photos and videos
- photo library permission is required only for importing existing media
- microphone permission is required for voice notes
- captured files must be saved locally before upload starts
- file limits should be enforced on-device before upload
- each media item needs independent retry state

Recommended services to add:

```text
JobWin/Services/MediaCapture/
JobWin/Services/UploadQueue/
```

Keep capture UI in feature screens, but keep file persistence and upload queue logic in services.

## Live Map And Location

Current behavior:

- foreground `When In Use` location sharing
- posts current device coordinates to mobile BFF
- deletes server location on explicit stop
- refreshes visible technicians every 20 seconds
- pauses when the app backgrounds

V1 next steps:

- add project/job address pins
- differentiate current user, technicians, and jobs visually
- show stale/fresh/unknown states
- show accuracy
- show when sharing is paused
- test on physical iPhone

Background tracking is not enabled by default.

## Push Notifications

Current code provides notification permission flow, APNs token callback bridge, registration endpoint call, and tapped notification route mapping.

Remaining Xcode/device work:

- signing team
- Push Notifications capability
- APNs entitlement
- physical device verification
- production push payload tests

## Web Fallbacks

Use Safari fallback for V1 when a route is valid but not native yet:

- estimate public/review pages
- invoice pages
- billing/admin surfaces
- rare settings

Fallbacks should be explicit and route-safe. Avoid opening arbitrary URLs from activity payloads.

## Adding A New Feature

Use this sequence:

1. define product behavior in docs or a feature worklist
2. confirm BFF endpoint and DTO shape
3. add DTOs to `MobileModels.swift`
4. add paths to `MobileAPI.swift`
5. implement service or feature model
6. implement SwiftUI screen
7. apply capability gating
8. add route/deep-link handling if needed
9. test loading, empty, error, and permission states
10. update `MOBILE_FEATURE_STATUS.md`

## Anti-Patterns

- direct database calls from iOS
- raw endpoint strings scattered in views
- actions visible to users who cannot execute them
- remote validation before local draft save
- deleting local draft/media on upload failure
- treating AI text as final estimate data
- adding background GPS without explicit product approval
- adding web parity screens before P1 native workflows
