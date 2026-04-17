# JobWin iOS Testing Checklist

Last updated: 2026-04-17

## Purpose

Use this checklist for every meaningful iOS change. The goal is to avoid blind development and make feedback actionable.

## Required Test Metadata

Record this in every test report:

```text
Tester:
Date:
Mac model:
macOS version:
Xcode version:
Repo commit:
Simulator/device:
iOS version:
Backend host:
Test account:
Build result:
Run result:
Screenshots/logs attached:
```

## Clean Setup

From a clean clone or updated checkout:

```bash
git checkout main
git pull
xcodegen generate
open JobWin.xcodeproj
```

Build from Xcode or CLI:

```bash
xcodebuild -project JobWin.xcodeproj -scheme JobWin -destination 'platform=iOS Simulator,name=iPhone 16' build
```

If `iPhone 16` is unavailable, list simulators in Xcode and use an installed iOS 17+ simulator.

## Smoke Test

### Launch

- app launches without crash
- auth gate appears when no session exists
- default API base URL is `https://app.jobwin.io`
- failed auth shows readable error
- successful auth opens app shell

### App Shell

- tabs render according to the user's role
- badges appear when backend returns counts
- returning app to active state refreshes visible data
- sign out clears session

### Home

- Home loads
- urgent tasks render
- follow-up queue renders
- missed-call queue renders if data exists
- shortcuts route correctly
- pull-to-refresh works

### Jobs

- Jobs list loads
- search/filter behavior works where available
- job detail opens
- job fields render correctly
- `Arrived` works or shows permission/error state
- `Start` works or shows permission/error state
- `Complete` works or shows permission/error state
- reschedule opens and preserves entered data on failure
- call/text/navigation actions are hidden when not allowed

### Clients

- Clients list loads
- search works
- client detail opens
- internal note can be added or shows readable error
- call/text/navigation actions are hidden when not allowed
- thread/job shortcuts route correctly when IDs exist

### Inbox

- Inbox list loads
- quick filters work
- thread detail opens
- internal note can be added or shows readable error
- client/call/text/navigation actions respect permissions

### Tasks

- Tasks list loads
- task detail opens
- complete task works or shows readable error
- task links from Home, Calendar, Client, and Job route correctly

### Activity Center

- bell opens activity center
- unread count renders
- mark-all-read works
- activity item tap routes correctly
- primary/secondary actions are hidden or downgraded when user lacks access
- estimate/invoice activity opens Safari fallback when native screen does not exist

### Deep Links

Run from Terminal after simulator boot:

```bash
xcrun simctl openurl booted jobwin://home
xcrun simctl openurl booted jobwin://calendar
xcrun simctl openurl booted jobwin://jobs
xcrun simctl openurl booted jobwin://clients
xcrun simctl openurl booted jobwin://inbox
xcrun simctl openurl booted jobwin://tasks
```

Expected:

- allowed routes open the correct screen
- blocked routes fall back safely
- invalid IDs show a readable state, not a crash

## Live Map And Location

Simulator can validate UI only. Physical iPhone is required for meaningful location behavior.

### Simulator

- Calendar opens
- `Agenda / Live Map` switch exists
- Live Map renders empty state when no pins exist
- refresh button works
- permission prompts do not crash the app

### Physical iPhone

- app is signed with a valid team
- location services are enabled
- `When In Use` permission prompt appears
- tapping `Share my location` changes state to active
- current device pin appears
- backend returns current user in technician list when expected
- moving the device updates location after time/distance threshold
- backgrounding the app pauses foreground sharing visibly
- tapping `Stop sharing` removes or expires current user location as expected

## AI Estimate From Media

This flow is not complete yet. Use this section as acceptance criteria when implementing it.

### Draft Foundation

- user can create a draft without client
- user can create a draft without job
- notes save locally immediately
- draft is still present after app restart
- local save state is visible

### Media Capture

- camera permission prompt works
- photo capture saves local file before upload
- short video capture saves local file before upload
- microphone permission prompt works
- voice recording saves local file before upload
- thumbnails/previews render
- capture limits are enforced before upload

### Upload Queue

- each media item shows status
- one failed upload does not remove other media
- retry one item works
- retry all failed items works
- app restart restores queued upload state

### AI Review

- analysis trigger is disabled until minimum data exists
- analysis errors do not erase draft data
- work items render as separate editable rows
- quantity/time/price are not collapsed into one item
- assumptions render
- missing inputs render
- confidence warnings render
- user can add more media and re-run analysis

### Conversion

- reviewed draft converts to estimate
- conversion failure preserves local draft
- success state links to the created estimate
- local read-only snapshot remains available for support/audit

## Push Notifications

Simulator push testing is limited. Physical device is preferred.

- Push Notifications capability is enabled
- APNs token callback fires
- registration endpoint is called after auth
- denied permission state is readable
- notification tap routes to the expected app route
- foreground push refreshes badges/activity

## Failure Modes To Capture

Attach screenshot and logs for:

- build failure
- launch crash
- auth failure
- blank screen
- infinite loading
- permission prompt failure
- backend `401`, `403`, `404`, `500`
- mutation success but UI not refreshing
- data entered then lost
- route/action visible but blocked later

## Test Report Template

```text
Summary:

Passed:
-

Failed:
-

Blocked:
-

Screenshots/logs:
-

Suggested priority:
- P0 / P1 / P2 / P3
```
