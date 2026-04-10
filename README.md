# JobWin iOS

Native SwiftUI operator app scaffold for JobWin.

## Scope

This folder is the starting point for the native iOS client that sits on top of the existing JobWin backend:

- `POST /api/mobile/v1/session`
- `GET /api/mobile/v1/bootstrap`
- `GET /api/mobile/v1/activity`
- `GET /api/mobile/v1/home`
- `GET /api/mobile/v1/calendar`
- `GET /api/mobile/v1/orders`
- `GET /api/mobile/v1/orders/:orderId`
- `GET /api/mobile/v1/inbox/threads`
- `GET /api/mobile/v1/inbox/threads/:threadId`
- `GET /api/mobile/v1/clients`
- `GET /api/mobile/v1/clients/:clientId`
- `GET /api/mobile/v1/tasks`
- `GET /api/mobile/v1/tasks/:taskId`

Initial app focus:

- Home
- Calendar
- Inbox
- Orders
- Clients

Current scaffold progress:

- token-based auth gate against the mobile BFF
- `TabView` app shell with role-aware tab visibility
- list screens for Home, Calendar, Inbox, Orders, and Clients
- Home stack now also exposes:
  - tasks list
  - task detail
- detail navigation for:
  - order detail
  - client detail
  - inbox thread detail
  - task detail
  - cross-links between client, order, and inbox thread detail screens
- mutation flows already wired in the iOS shell:
  - complete urgent task from Home
  - client `ring-out` directly from the Home follow-up queue
  - client SMS deep-link from the Home follow-up queue
  - `Open thread` shortcut from the Home follow-up queue
  - `Latest order` shortcut from the Home follow-up queue
  - turn-by-turn navigation from Home order cards
  - missed-call drill-in from Home into inbox thread detail
  - `Thread` shortcut from the Home missed-calls queue
  - `Client` shortcut from the Home missed-calls queue
  - `Call` shortcut from the Home missed-calls queue
  - `Text` shortcut from the Home missed-calls queue
  - `Navigate` shortcut from the Home missed-calls queue
  - order `arrived / start / complete` actions from order detail
  - order `reschedule` flow from order detail
  - client SMS deep-link from order detail
  - order navigation from order detail
  - client `ring-out` from Orders list swipe action
  - client SMS deep-link from Orders list swipe action
  - order navigation from Orders list swipe action
  - order `arrived / start / complete` swipe actions from Calendar
  - client `ring-out` from Calendar swipe action
  - client SMS deep-link from Calendar swipe action
  - order navigation from Calendar swipe action
  - task completion directly from order detail
  - task completion from dedicated Tasks list
  - task completion from dedicated task detail
  - client `ring-out` from client detail
  - client SMS deep-link from client detail
  - client navigation from client detail
  - client `ring-out` from Clients list swipe action
  - client SMS deep-link from Clients list swipe action
  - client navigation from Clients list swipe action
  - `Open thread` shortcut from Clients list
  - `Latest order` shortcut from Clients list
  - client `ring-out` from inbox thread detail
  - client SMS deep-link from inbox thread detail
  - client navigation from inbox thread detail
  - add internal note from client detail
  - add internal note from inbox thread detail
- shared formatting and detail-card components for the next mutation pass
- shared formatting helper cleaned up so list/detail metadata separators render consistently
- primary list and detail screens now support pull-to-refresh against the mobile BFF
- primary list screens now support local search:
  - Orders
  - Clients
  - Inbox
- Inbox also includes local quick filters:
  - All
  - Unread
  - Follow-up
- app-level deep-link routing skeleton now exists for:
  - `jobwin://home`
  - `jobwin://calendar`
  - `jobwin://tasks`
  - `jobwin://task/<id>`
  - `jobwin://orders`
  - `jobwin://order/<id>`
  - `jobwin://inbox`
  - `jobwin://thread/<id>`
  - `jobwin://clients`
  - `jobwin://client/<id>`
  - push payload aliases now also map:
    - `booking` / `bookings` -> order flows
    - `payment` / `payments` -> billing web fallback
    - `message` / `thread` / `communication` -> inbox thread flows
    - `ai_call` / `ai_calls` / `phone_interaction` -> inbox
- web-fallback routing now also exists for non-native surfaces:
  - estimate paths
  - invoice paths
  - these open the matching JobWin web surface inside a native Safari sheet instead of dropping the push/deep link
- iOS push skeleton now exists:
  - `UNUserNotificationCenter` permission flow
  - `UIApplicationDelegate` bridge for APNs token callbacks
  - `POST /api/mobile/push/register` registration using the current authenticated mobile session
  - APNs payload -> `AppRoute` mapping for tapped notifications
- Home now exposes a native settings/diagnostics sheet with:
  - workspace/account summary
  - AI phone status from `/api/mobile/bootstrap`
  - push authorization + registration diagnostics
  - manual notification refresh/re-register action
  - direct jump to iPhone Settings when notifications are denied
- Home now also exposes a native activity center:
  - bell button with unread badge
  - `GET /api/mobile/activity`
  - `POST /api/mobile/activity` with `markAllRead`
  - taps on activity items route into the existing app router
  - activity items now also expose compact route-aware quick-open actions
    - primary target action
    - secondary collection fallback where it helps (`All orders`, `All clients`, `All inbox`, etc.)
  - estimate/invoice activity falls back to a native Safari sheet when no native screen exists yet
  - unread activity is now also mirrored to the iOS app icon badge
- app shell tab badges now mirror the operator queue using `/api/mobile/home`:
  - Home -> urgent tasks
  - Orders -> today orders
  - Inbox -> unread inbox
  - Clients -> follow-up queue
  - badges are also refreshed after task completion and order field mutations from native screens
  - badges and activity snapshot are also refreshed when:
    - the app returns to active state
    - a foreground push arrives
- Settings now also exposes native notification preference toggles backed by the mobile activity endpoint:
  - orders
  - clients
  - bookings
  - payments
  - AI calls
  - estimates
  - system
  - popup alerts
- task surfaces are now linked from multiple places:
  - Home urgent tasks
  - Calendar tasks
  - Client recent tasks
  - Order tasks
- mobile order summaries now include lightweight client call context for list-level quick actions:
  - `clientId`
  - `clientPhone`
- mobile client summaries now also include lightweight address context for list-level navigation:
  - `address`
- mobile client summaries now also include lightweight thread/order navigation context:
  - `threadId`
  - `latestOrderId`

## Notes

- This scaffold is source-first. It does not include a checked-in `.xcodeproj`.
- `project.yml` is included so the project can be generated on macOS with XcodeGen.
- `project.yml` now also registers the `jobwin` custom URL scheme for deep-link testing.
- Push Notifications capability / signing entitlement still needs to be finalized during the first macOS/Xcode build pass.
- Auth transport is bearer-token based and targets the JobWin mobile BFF.
- This environment does not include Xcode or a Swift toolchain, so source edits here are not compiler-verified.

## Local setup on macOS

1. Install Xcode.
2. Install XcodeGen if needed.
3. Run:

```bash
xcodegen generate
open JobWin.xcodeproj
```

For the first real build/debug pass, use:

- [BUILD_ON_MAC.md](D:\CodexWorkspace\repos\jobwin-ios\BUILD_ON_MAC.md)

## Current assumptions

- Minimum iOS target: 17.0
- Primary runtime host: `https://app.jobwin.io`
- Native app uses `Authorization: Bearer <Supabase access token>`
- Native VoIP is explicitly out of scope for v1
