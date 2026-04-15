# JobWin iOS Development Guide

Last updated: 2026-04-15

## Purpose

This guide keeps parallel iOS development aligned. Use it before making non-trivial changes.

## Before Starting Work

Read these files in order:

1. `README.md`
2. `BUILD_ON_MAC.md`
3. `docs/MOBILE_PRODUCT_DIRECTION.md`
4. `docs/MOBILE_ARCHITECTURE.md`
5. `docs/MOBILE_FEATURE_STATUS.md`
6. feature-specific worklist, if one exists

For estimate media work, also read:

```text
docs/AI_ESTIMATE_FROM_MEDIA_IOS_WORKLIST.md
```

## Branching

Use focused branches:

```text
codex/<short-feature-name>
fix/<short-bug-name>
```

Keep one branch to one product area when possible:

- auth
- estimate media
- live map
- orders
- clients
- inbox
- push
- design polish

## Build Rule

Every change should build locally before review:

```bash
xcodegen generate
xcodebuild -project JobWin.xcodeproj -scheme JobWin -destination 'platform=iOS Simulator,name=iPhone 16' build
```

If the simulator name differs, use an installed iOS 17+ simulator.

## Adding A Screen

Use this pattern:

1. create or update DTOs in `JobWin/Core/Models/MobileModels.swift`
2. add endpoint path in `JobWin/Core/Networking/MobileAPI.swift`
3. fetch through `APIClient`
4. add screen under the matching `JobWin/Features/<Area>/` folder
5. inject `SessionStore` or `APIClient`
6. handle loading, empty, error, and success states
7. add route handling in `AppNavigation.swift` if needed
8. update docs and testing checklist

Do not put raw endpoint strings directly inside views.

## Adding A Mutation

Required behavior:

- disable duplicate taps while request is in flight
- show readable backend errors
- refresh affected screen data after success
- preserve user input after failure
- hide or disable action when capability is missing

For form-like mutations, local state should survive validation failure.

## Adding Local Persistence

Use local persistence when data is expensive to recreate:

- captured media
- voice notes
- estimate draft notes
- upload queue state
- retry errors

Rules:

- save locally before calling backend
- scope user data by workspace and user when possible
- keep local data after upload or validation failure
- distinguish local save from remote sync
- add manual delete for abandoned local drafts when appropriate

## Adding Permission-Gated Actions

Never show an action only to let the backend reject it later.

Required sequence:

1. confirm backend route permission
2. confirm bootstrap capability or role data
3. gate the visible action
4. gate router/deep-link target
5. keep backend enforcement
6. add checklist entry

Examples:

- ring-out should be hidden without ring-out capability
- inbox/client routes should be hidden for limited roles when router blocks them
- activity center CTAs should be filtered before display

## Estimate Media Development Rules

The estimate media flow is the top native priority.

Non-negotiables:

- create local draft first
- allow draft without client
- allow draft without order
- save notes immediately
- save captured files locally before upload
- upload media independently
- preserve successful media when another file fails
- show retry status per item
- render AI work items separately
- require human review before conversion

Recommended implementation order:

1. `EstimateDraftListView`
2. `EstimateDraftComposerView` with notes and local save
3. client/order binding
4. photo capture
5. voice recording
6. short video capture
7. upload queue
8. analysis trigger
9. review screen
10. conversion

## Live Map Development Rules

Current location sharing is foreground-first.

Next live map work should add:

- project/job address pins
- pin legend
- freshness and accuracy labels
- clear sharing state
- blocked permission state
- physical-device verification

Do not enable background location without product approval.

## UI Standards

Use the existing design system:

```text
JobWin/Core/DesignSystem/DesignSystem.swift
```

Guidelines:

- keep screens readable one-handed
- prefer clear sections over dense web-like tables
- use native controls where possible
- provide empty states
- provide retry actions
- keep destructive actions explicit
- avoid hiding important failures in console logs only

## Documentation Updates

When a feature changes, update at least one of:

- `docs/MOBILE_FEATURE_STATUS.md`
- `docs/MOBILE_TESTING_CHECKLIST.md`
- feature worklist under `docs/`
- `README.md` if the app scope or setup changes

## Pull Request Checklist

Before opening or merging a PR:

- code builds
- feature was tested in simulator or physical device
- screenshots or notes are attached for visible UI changes
- permission behavior was checked
- local data preservation was checked for user-entered forms
- docs were updated
- no generated Xcode project files were committed unless intentionally approved
