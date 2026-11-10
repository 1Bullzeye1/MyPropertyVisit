# Release checklist and SDLC record

Launch scope is frozen to current offline features. Open items below do not authorize expanding the scope. “Prepared” documents and prior successful tests are not evidence that a release archive passed all checks.

## Requirements and design

- [x] Capture the offline launch scope, explicit exclusions and limitations.
- [x] Record owner decision: USD 4.99 one-time iOS paid download.
- [x] Prepare user guide, listing, privacy/support drafts and privacy inventory.
- [ ] Finalize legal seller identity, country, support mailbox, brand/domain and launch territories.
- [x] Select product name: MyPropertyVisit.
- [ ] Complete store-name/brand review and confirm domain registration before public branding.

## Implementation readiness

- [ ] Replace Start a property call with an accurate property-creation label; remove Join a call, Live tours and coming-soon calling claims from launch UI.
- [ ] Add accessible public privacy/support links once final URLs exist.
- [ ] Audit required-reason APIs and include/validate PrivacyInfo.xcprivacy in the archive.
- [ ] Confirm profile controls remain clearly local and do not imply authentication.
- [ ] Ensure backup/export limitations and manual dimension entry are discoverable before reliance on the app.
- [ ] Review video/session deletion limitation and confirm policy accuracy. A deletion feature is not claimed as implemented.

## Test matrix — record device, OS, build, result and evidence

| ID | Test | Acceptance |
| --- | --- | --- |
| QA-01 | First install, first launch after update, repeated launch | No unexplained blank startup; measure system launch separately from the deliberate 2-second artwork hold |
| QA-02 | Camera allowed/denied and permission changed in Settings | Clear feedback; existing records remain accessible |
| QA-03 | Compass valid/unavailable/interference | Visible valid directions or unavailable state; no invented bearings |
| QA-04 | Photos before video and during pause | Photos saved in correct visit with compass; pause flow tested on iOS 18+ |
| QA-05 | Repeated pause/resume; stop while paused | One playable silent video, compass timeline matches recorded time |
| QA-06 | Background, lock, phone interruption, camera in use | No crash; saved/failure state explicit; confirm finalized video |
| QA-07 | Wide/telephoto presets and portrait/landscape | Hardware-safe options; preview/export orientation and compass in bounds |
| QA-08 | Room assignment and manual values | Shared details only for same room; categories do not merge distinct rooms; invalid/partial dimensions rejected |
| QA-09 | Gallery and full-screen viewing with representative media volume | Responsive browsing; measured behavior with large library; no lost edits |
| QA-10 | Single/multi/all photo+video export | Count matches, compass present, destination files open; denied Photos permission handled |
| QA-11 | Partial export failure and low storage | Failed items identifiable; successful saves not repeated on retry; originals retained |
| QA-12 | App update over existing installation | Properties, profile, sessions, room links and media retained |
| QA-13 | Profile/property/photo deletion | Exact scope verified; no misleading cascade or recovery promise |
| QA-14 | iPad, Dynamic Type, VoiceOver, reduced motion, themes | Controls reachable/readable; supported orientation works |
| QA-15 | Offline operation | Capture/edit/playback work; sharing destination connectivity is separate |

Previous evidence: iOS Release builds and photo/export-copy regression checks passed during export work; user confirmed the missing share-icon fix. These are partial evidence, not a completed matrix. Android emulator results are tracked in its repository.

## TestFlight

- [ ] Distribute the same candidate build intended for release to independent testers.
- [ ] Use demo properties or permissioned real property content.
- [ ] Record device/OS and test sequence, issues, severity, fix commit and retest result.
- [ ] Have testers complete an actual property visit and export its media without developer assistance.
- [ ] Resolve data-loss, crash, corrupt media and privacy-description mismatches before sale.

## Store and operations

- [ ] Active developer membership and valid distribution signing.
- [ ] Paid Apps agreement, tax and banking information complete in official portals.
- [ ] Price, territories and release method configured; Small Business enrollment status verified if used.
- [ ] Real screenshots, metadata, age/content-rights questionnaires and privacy answers complete.
- [ ] Privacy/support pages public, no sign-in required, no placeholders; support mailbox tested.
- [ ] Validate upload with current App Store Connect requirements, including SDK/signing/privacy checks.
- [ ] Review final archive, symbols, version/build and export compliance answers for actual implementation.
- [ ] Commit/push current source to iOS repository; preserve history. Do not reuse the November 6 tag for later changes.
- [ ] Obtain review result and perform explicit manual release when ready.

## Release record — fill when actions actually occur

| Field | Value |
| --- | --- |
| Version / build | Pending final archive; source currently 1.0 / 2 |
| Release commit / tag | Pending |
| Archive / symbols location | Pending |
| TestFlight build and acceptance evidence | Pending |
| Public policy/support URLs | Pending |
| Owner release decision | Pending |
| App Store review / publication date | Pending |

## Maintenance

Monitor the support inbox and App Store diagnostics available under platform settings. Triage crashes, data loss and broken capture/export first. Keep a reproduction record and retest fixes against retained app data. A code rollback is not a user-device restore: fixes for shipped builds require an updated reviewed build. Preserve compatibility with existing saved records. Review documentation/privacy again whenever storage, SDKs, calling, accounts or monetization changes.
