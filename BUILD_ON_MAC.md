# JobWin iOS Build Handoff

This scaffold is source-ready, but it has not been compiler-verified in the current Windows session because the required macOS toolchain is unavailable here.

## Current blocker

The current environment does not expose:

- `xcodebuild`
- `xcodegen`
- `swift`
- XcodeBuildMCP simulator/build tools

Build and simulator verification must happen on macOS.

## Expected first build flow on macOS

1. Install:
   - Xcode
   - Xcode Command Line Tools
   - XcodeGen

2. Generate the project:

```bash
cd /path/to/jobwin-ios
xcodegen generate
open JobWin.xcodeproj
```

3. In Xcode, set:
   - Team / signing
   - valid bundle id if `io.jobwin.mobile` must be changed
   - Push Notifications capability
   - Background Modes only if later needed

4. Build the `JobWin` scheme on an iPhone simulator.

5. Verify these first:
   - app launches to auth gate
   - token paste / auth session flow
   - Home loads
   - tab navigation works
   - push permission prompt path works
   - custom URL scheme `jobwin://...` resolves
   - Calendar `Agenda / Live Map` switch renders both modes

## Runtime prerequisites

The app expects the backend at:

- `https://app.jobwin.io`

The native app uses:

- `Authorization: Bearer <Supabase access token>`

The mobile backend endpoints already exist in the web repo.

## First compile-risk areas to check

These files are the highest-value first compile targets because they carry the newest shell work:

- `JobWin/App/AppRoot.swift`
- `JobWin/App/AppNavigation.swift`
- `JobWin/Core/Models/MobileModels.swift`
- `JobWin/Core/Networking/APIClient.swift`
- `JobWin/Features/Home/HomeView.swift`
- `JobWin/Features/Calendar/CalendarView.swift`
- `JobWin/Features/Map/LiveMapView.swift`
- `JobWin/Features/Orders/OrdersView.swift`
- `JobWin/Features/Orders/OrderDetailView.swift`
- `JobWin/Features/Clients/ClientsView.swift`
- `JobWin/Features/Settings/ActivityCenterView.swift`
- `JobWin/Services/Location/LocationService.swift`
- `JobWin/Services/Push/PushService.swift`

## Capabilities to finish in Xcode

These still require real Xcode setup:

- Push Notifications entitlement
- signing profile validation
- simulator/device run verification
- APNs behavior verification
- foreground location permission prompt verification
- physical-device live location verification

## Suggested first verification sequence

1. Generate project with XcodeGen
2. Fix any compile errors
3. Boot simulator
4. Launch app
5. Verify:
   - Home
- Jobs list/detail
   - Clients list/detail
   - Inbox thread detail
   - Activity center
   - deep links
   - Calendar `Agenda`
   - Calendar `Live Map`
6. Then verify mutations:
   - task complete
   - order arrived/start/complete
   - reschedule
   - ring-out request dispatch
7. On a physical iPhone, verify live location:
   - allow `When In Use` location permission
   - open Calendar -> `Live Map`
   - tap `Share my location`
   - confirm your pin appears and refreshes
   - move the device and confirm position updates after distance/time threshold
   - background the app and confirm the UI reflects paused sharing instead of pretending to track in background

## Backend state at handoff

The backend/mobile BFF is already build-green in `contractor-ai-os`:

- `pnpm lint` passed
- `pnpm build` passed

The iOS shell currently relies on those routes and DTOs being available.
