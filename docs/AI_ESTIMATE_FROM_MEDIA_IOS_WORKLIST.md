# AI Estimate From Media iOS Worklist

Last updated: 2026-04-14

## Purpose

This document locks the iOS worklist for the first JobWin flow where an operator captures site photos, short video, and voice notes, then receives an AI-generated estimate draft.

This is the client-side companion to the backend worklist in `contractor-ai-os/docs/architecture/ai-estimate-from-media-backend-worklist.md`.

## Locked Direction

- The iOS app owns capture, local draft persistence, and upload retry.
- Media must be saved locally before backend analysis begins.
- A user must not lose captured data because client selection, validation, or later analysis fails.
- The app must show structured AI suggestions, not a blob of text.
- Human review remains required before final estimate conversion.

## Product Scope

The iOS app must support:

1. creating a draft estimate before all details are complete
2. attaching photo, video, and voice note inputs
3. local autosave and recovery after app restart
4. upload queue with per-file status and retry
5. triggering AI analysis
6. reviewing suggested work items, time range, price range, and missing inputs
7. editing or confirming the suggestion before conversion

## Non-Goals

- final estimate approval without review
- direct dependency on CompanyCam for the primary flow
- silent data loss when validation fails
- free-form AI summary as the only review surface

## Required Native Surfaces

### `EstimateDraftListView`

Purpose:
- list in-progress drafts and failed drafts that need attention

Must show:

- draft title or placeholder
- client binding if available
- last updated time
- upload or analysis status
- retry-needed state

### `EstimateDraftComposerView`

Purpose:
- primary capture and edit surface before AI analysis

Must support:

- attach or change client
- attach or change order
- add notes
- add photos
- add short video
- add voice note
- local draft save indicator
- upload progress per media item

### `EstimateDraftReviewView`

Purpose:
- review AI output before estimate conversion

Must show:

- suggested work items as separate rows
- time range
- price range
- assumptions
- missing inputs
- follow-up questions
- warnings when confidence is low

## Local State Model

Suggested client-side entities:

```swift
struct EstimateDraftLocalRecord: Codable, Identifiable {
    let id: String
    var clientId: String?
    var orderId: String?
    var title: String?
    var notes: String
    var status: DraftStatus
    var analysisStatus: DraftAnalysisStatus
    var pricingStatus: DraftPricingStatus
    var localMedia: [EstimateDraftLocalMedia]
    var updatedAt: Date
}
```

```swift
struct EstimateDraftLocalMedia: Codable, Identifiable {
    let id: String
    let localURL: URL
    var remoteId: String?
    var kind: MediaKind
    var uploadStatus: UploadStatus
    var processingStatus: ProcessingStatus
    var lastErrorMessage: String?
}
```

Rules:

- local draft record is written before upload begins
- local files remain until server upload and processing succeed
- app relaunch must restore drafts from disk
- upload retry must operate per media item, not only per draft

## Required Platform Capabilities

- camera permission
- photo library permission if importing existing media
- microphone permission for voice notes
- temporary file storage for queued uploads
- background-safe state restoration for interrupted sessions

## UX Rules

- never block local save on missing client or order selection
- show `Saved locally` separately from `Uploaded`
- if one upload fails, keep successful uploads attached
- if AI returns multiple work types, show them as separate items
- if AI needs more data, surface a clear next step instead of generic failure text
- if the draft is incomplete, allow the operator to keep editing without losing prior output

## iOS Worklist

### Phase A: Draft Foundation

- [x] add native estimate draft domain models
- [x] add local persistence for draft metadata
- [x] add local persistence for queued media metadata
- [ ] add draft list screen for in-progress work
- [ ] add resume-draft entry point from Home or Orders

### Phase B: Media Capture

- [ ] add photo capture flow
- [ ] add short video capture flow
- [ ] add voice note recording flow
- [ ] generate local thumbnails and previews
- [ ] enforce client-side capture limits before upload

### Phase C: Autosave And Recovery

- [ ] save draft immediately after each capture step
- [ ] restore drafts after app restart
- [ ] restore failed uploads after app restart
- [ ] surface `saved locally` vs `uploaded` states in UI
- [ ] allow manual delete of abandoned local drafts

### Phase D: Upload Queue

- [ ] implement per-file upload queue manager
- [ ] make uploads idempotent by draft and media item
- [ ] store retryable failure reasons
- [ ] add retry action for one failed media item
- [ ] add retry action for all failed items in a draft

### Phase E: Analysis Flow

- [ ] add `Analyze` action for completed drafts
- [ ] poll or refresh draft analysis status
- [ ] show `uploading`, `processing`, `needs input`, and `ready for review` states
- [ ] display backend analysis errors without wiping local draft data

### Phase F: Review And Edit

- [ ] render work items as separate editable rows
- [ ] show time and price ranges from backend pricing output
- [ ] show assumptions and missing inputs
- [ ] allow note edits after AI analysis
- [ ] allow adding extra media and re-running analysis

### Phase G: Conversion

- [ ] add confirm action for reviewed draft
- [ ] add convert-to-estimate action
- [ ] show conversion success state and destination
- [ ] preserve local read-only snapshot for audit and support troubleshooting

## Acceptance Criteria

- a user can capture media before selecting a client
- media is still present after app restart
- one failed media upload does not delete the rest of the draft
- AI review screen shows separate work items instead of a collapsed single item
- the app clearly distinguishes `saved locally`, `uploaded`, `processing`, and `needs input`
- the user can add more media and retry analysis without rebuilding the draft from scratch
