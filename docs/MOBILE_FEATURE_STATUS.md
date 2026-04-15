# JobWin iOS Feature Status

Last updated: 2026-04-15

Status legend:

- `Ready`: implemented and expected to work, pending normal regression testing
- `Scaffold`: structure exists, but UX or end-to-end behavior is incomplete
- `Partial`: useful behavior exists, but important pieces are missing
- `Missing`: not implemented yet
- `Blocked`: cannot be completed without external setup or backend work
- `Not planned for V1`: intentionally out of scope for the first native release

## Executive Summary

The iOS app is currently a functional scaffold. It has the main shell, several native data surfaces, routing, location foundation, and activity integration. It is not yet a finished mobile product.

The next work should focus on:

1. Mac/Xcode testability
2. user-facing auth
3. AI estimate from camera, video, and voice
4. live map with job address pins and technician/device tracking
5. polish of core operator flows

## Feature Matrix

| Area | Status | Current State | Next Step |
| --- | --- | --- | --- |
| Xcode project generation | Ready | `project.yml` generates `JobWin.xcodeproj` with XcodeGen | Keep generated project out of repo unless team decides otherwise |
| Simulator build loop | Blocked | Needs Mac/Xcode verification | Run clean build on Mac and fix compile/runtime issues |
| Physical device loop | Blocked | Signing and capabilities not finalized | Configure Apple Team, bundle id, push entitlement |
| Auth | Scaffold | API base URL plus Supabase access token paste | Add email/password mobile sign-in and password reset path |
| Session persistence | Partial | Token stored in Keychain, base URL in UserDefaults | Validate refresh and expired-token UX on device |
| App shell | Partial | Tab shell, role-aware tab visibility, badges | Polish empty/error/loading states and navigation consistency |
| Home | Partial | Operator queues and shortcuts exist | Field-test with real data and tighten layout |
| Calendar agenda | Partial | Orders/tasks agenda exists | Add stronger filtering, date navigation, and empty states |
| Calendar live map | Scaffold | Technician pins and current device sharing exist | Add job/project address pins and map legend |
| Orders list/detail | Partial | List/detail/actions exist | Verify all mutations and stale data refresh |
| Order status mutations | Partial | Arrived/start/complete wired | Device-test permission, errors, refresh, and optimistic state |
| Order reschedule | Partial | Native reschedule sheet exists | Validate date/time UX and backend error preservation |
| Clients list/detail | Partial | List/detail/notes/quick actions exist | Add create/edit client if prioritized for mobile |
| Inbox | Partial | Thread list/detail and notes exist | Verify message freshness and filters against real inbox data |
| Tasks | Partial | List/detail/complete exists | Verify cross-links from Home, Calendar, Client, Order |
| Activity Center | Partial | Feed, mark all read, route-aware actions, gating work done | Device-test role-specific CTA visibility |
| Push notifications | Scaffold | Permission, APNs callback bridge, registration skeleton | Configure signing/capability and test physical device |
| Deep links | Scaffold | Core `jobwin://` routes exist | Run simulator deep-link smoke tests |
| Web fallbacks | Partial | Estimate/invoice fallback via Safari sheet | Document every fallback route and add safe URL tests |
| Live location sharing | Scaffold | Foreground sharing to BFF exists | Test physical iPhone and add job address pins |
| Background location | Missing | Not enabled by design | Product decision required before implementing |
| Estimate draft local store | Partial | Local draft and media metadata persistence exists | Add screens and upload queue |
| Estimate draft list | Missing | No native list screen yet | Add `EstimateDraftListView` |
| Estimate draft composer | Missing | No capture/edit composer yet | Add client/order binding, notes, media capture UI |
| Photo capture | Missing | Not implemented | Add camera capture and local file persistence |
| Video capture | Missing | Not implemented | Add short video capture and limits |
| Voice note capture | Missing | Not implemented | Add microphone permission and recording flow |
| Media upload queue | Missing | Not implemented | Add per-file upload/retry service |
| AI analysis trigger | Missing | Not implemented in iOS | Add analyze action after upload readiness |
| AI review screen | Missing | Not implemented | Render separate editable work items, assumptions, ranges |
| Estimate conversion | Missing | Not implemented in iOS | Add reviewed draft to estimate conversion |
| CompanyCam dependency | Not planned for V1 | Primary flow should not depend on CompanyCam | Keep optional integration discussion separate |
| Native invoice editing | Missing | Web fallback only | Prioritize only after estimate flow if needed |
| Native billing/admin | Missing | Web app remains primary | Keep as web fallback for V1 |
| Native VoIP | Not planned for V1 | Explicitly out of scope | Use existing call/ring-out backend flows |

## P1 Implementation Backlog

### 1. Development Visibility

- clean Mac build
- simulator smoke test
- physical device smoke test
- screenshot/log capture workflow
- repeatable test checklist

### 2. Mobile Auth

- add user-facing login screen
- support email/password against backend-approved auth route
- support password reset or safe web fallback
- remove token paste from normal user flow
- keep developer token mode only if hidden behind debug build flag

### 3. AI Estimate From Media

- add draft list
- add draft composer
- add local photo capture
- add short video capture
- add voice recording
- add local autosave indicators
- add upload queue
- add retry UI
- add analysis trigger
- add structured review screen
- add conversion flow

### 4. Live Map

- add job/project address pins from calendar/orders payload
- show current user and technicians distinctly
- show freshness and accuracy
- show paused/blocked/active sharing states clearly
- test foreground location on a physical iPhone

### 5. Core Flow Polish

- review all empty states
- review all error states
- verify role-based action visibility
- verify refresh after mutations
- tune one-handed mobile layouts
- reduce places where web fallback feels surprising

## Definition Of Done For New Native Features

A feature is not done until:

- it builds on Mac
- it runs in Simulator
- loading, empty, error, and success states exist
- permission-denied state exists if relevant
- backend errors do not erase local user input
- role-gated actions match backend capabilities
- docs are updated
- the test checklist includes the feature
