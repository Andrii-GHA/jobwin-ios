# JobWin iOS Product Direction

Last updated: 2026-04-17

## Purpose

The iOS app is the native field and operator companion for JobWin. It should not try to clone every web screen. It should make the highest-friction mobile work faster, safer, and more reliable than the web app on a phone.

The app exists for three primary jobs:

1. let operators and technicians act on daily work quickly
2. capture job-site context with camera, video, voice, and location
3. preserve field input even when validation, network, or AI processing fails

## Product Principles

- Native first for mobile-only workflows: camera, microphone, location, push notifications, quick actions, local recovery.
- Web remains the system of record and admin surface.
- The iOS app should use the mobile BFF, not direct database access.
- Data entered on the phone must be saved locally before remote validation or AI analysis.
- AI output must be reviewable as structured work items, not only as free text.
- Permissions must be enforced in the UI before a blocked backend request is possible.
- When a feature is not native yet, use a deliberate Safari fallback instead of silently dropping the route.

## V1 Product Promise

V1 should be good enough for a real operator or technician to:

- sign in without developer-only token handling
- see today's work and urgent follow-up items
- open jobs, clients, inbox threads, and tasks
- perform common field actions from native screens
- create an estimate draft from voice, photos, and short video
- review AI-suggested work items before creating an estimate
- share live foreground location while the app is open
- view technician/device locations and project/job addresses on a map
- receive and route push notifications into the correct native or fallback screen

## Priority Order

### P0: Make Development Testable

Before large feature work, the team needs a repeatable Mac/Xcode loop:

- generated project builds from a clean clone
- simulator run is documented
- physical device run is documented
- screenshots and logs can be captured for review
- compile errors are fixed before adding large UX flows

### P1: Normal Mobile Authentication

Current state is token-based developer login. V1 needs a user-facing auth flow:

- email/password sign in
- password reset entry point or clear web fallback
- persisted session
- sign out
- readable errors for expired or unauthorized sessions

### P1: AI Estimate From Media

This is the main product differentiator.

Required native flow:

- create local draft first
- attach or defer client/order binding
- add typed notes
- capture photos
- capture short video
- record voice note
- show local save status
- upload media with retry
- trigger AI analysis
- render suggested work items as separate editable rows
- show time, price, assumptions, missing inputs, and confidence warnings
- convert reviewed draft to an estimate

### P1: Live Map And Device Tracking

The app should show field context clearly:

- current user's device location
- other visible technicians
- job/project address pins
- freshness and accuracy indicators
- foreground sharing state
- explicit paused state in background

Background GPS is not a V1 default. Add it only after product and battery tradeoffs are accepted.

### P2: Core Operator Flows

Native surfaces should cover the most common daily actions:

- Home queues
- Calendar agenda
- Jobs list and detail
- Clients list and detail
- Inbox list and thread detail
- Tasks list and detail
- notes
- job status mutations
- reschedule
- call, SMS, and navigation shortcuts where permitted

### P2: Push And Activity Routing

Push and activity items should route into:

- native detail screens when native support exists
- Safari fallback for estimate, invoice, billing, or admin-only surfaces
- Home as a safe fallback when a route is not allowed by the user's role

## V1 Non-Goals

- full native replacement for the web app
- native admin/business configuration screens
- native billing management
- native invoice editing unless explicitly prioritized
- direct dependency on CompanyCam for the primary estimate flow
- native VoIP or CallKit
- silent background GPS
- final AI estimate approval without human review
- direct Supabase table access from iOS

## Decision Rules

Use these rules when adding new features:

1. If the workflow needs camera, microphone, GPS, push, local recovery, or quick field action, prefer native.
2. If the workflow is admin-heavy, billing-heavy, or rarely used, prefer web fallback for V1.
3. If data loss is possible, add local persistence before remote calls.
4. If backend permissions can reject the action, hide or downgrade the action in iOS first.
5. If a route has no native screen yet, route to Safari fallback only when the URL is safe and intentional.
6. If a feature needs new data, add or extend the mobile BFF contract first.

## Current Product Readiness

The app is currently a functional scaffold, not a finished mobile product.

Current strengths:

- app shell and navigation exist
- primary data surfaces exist
- many quick actions are wired
- location sharing foundation exists
- activity center and permission gating are started
- local estimate draft storage foundation exists

Current gaps:

- token-based login is still developer-oriented
- AI estimate from media is not yet implemented end to end
- capture, upload, analysis, review, and conversion screens are missing
- live map does not yet show project/job address pins as a first-class layer
- push signing and APNs testing need real Xcode/device setup
- UI polish and full device testing are still required
