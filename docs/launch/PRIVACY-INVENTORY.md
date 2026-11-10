# Privacy inventory and proposed store declarations

Source review: 10 November 2026. This is an engineering evidence sheet, not a submitted store declaration. Verify the final signed archive and all bundled dependencies before answering the store forms.

| Data / access | Current purpose | Location / recipient | Evidence |
| --- | --- | --- | --- |
| Property name/type/address | Organize a property | UserDefaults in local container | ContentView.swift Property model and store |
| Profile name/email/role | Optional local profile | AppStorage/UserDefaults | LocalProfileView |
| Theme | Appearance preference | Local preferences | LensSettingsView |
| Rear-camera photo/video | Property capture | Local Documents | CameraEngine, Walkthrough, RoomPhotoStore |
| Microphone | Not used; silent recordings | No audio input configured | CameraEngine and permission settings |
| Magnetic heading/accuracy/time | Compass display/export | Local video metadata; visible photo/video compass on export | CLLocationManager heading delegate, HeadingSample |
| GPS coordinates | No GPS position retrieval found | Not collected by reviewed code | No startUpdatingLocation/request-location implementation found |
| Room dimensions/notes | Manual room records | Local rooms-v2.json index | RoomPhotoStore |
| Capture visit records | Group captures | Local CaptureSessions JSON | CaptureVisit |
| Photos save | User-selected export | Apple Photos via add-only access | MediaExportView, NSPhotoLibraryAddUsageDescription |
| Sharing | User-selected files | Destination chosen in system share sheet | UIActivityViewController |
| Diagnostics | Startup timings/messages | OS logging | MyPropertyVisitApp Logger; no third-party reporting SDK found |
| Support correspondence | User voluntarily emails support | Future chosen mailbox provider | Operational setup pending |

## Source review findings

No MyPropertyVisit network client, authentication service, advertising SDK, analytics SDK or contacts access was found in reviewed first-party iOS source. That finding is not proof of zero platform traffic. Purchases, OS diagnostics, device backups, chosen share destinations and website hosting have their own handling.

Proposed App Store privacy answer: **Data Not Collected**, only if final binary/dependency and support-flow review supports it under Apple's definitions. Local storage alone is not the same as developer collection. Review any voluntary support-data exception against all criteria rather than silently ignoring support attachments. If an analytics SDK, in-app support uploader or cloud service is added, reassess the answers before shipping.

Apple defines collection around transmission off-device with developer/partner access beyond real-time request servicing. See [Apple's privacy definitions and disclosure exceptions](https://developer.apple.com/app-store/app-privacy-details/). This assessment does not prefill or submit the form.

## Required-reason API audit

UserDefaults and file modification-date access are present. No first-party PrivacyInfo.xcprivacy file was found during this review. Before submission, inventory required-reason APIs in the final target/dependencies, add the applicable approved reasons, include the manifest in the archived app and validate the archive privacy report. Do not copy reason codes without checking their actual allowed use. This is an open release task, not a change made by documentation.

Source: [Required-reason API documentation](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api).

## Backup and deletion accuracy

No app-managed cloud sync or backup/restore. iOS Documents/preferences may be included in device backups. Photo export is a separate copy. Property/profile removal is not a cascade across all media. No video/session deletion UI was found. The public policy must preserve these distinctions until implementation changes.

## Publication check

Compare this inventory, privacy policy, in-app permission text, public website and store answers against the same archive. Replace legal/contact placeholders. Host policy/support publicly and add accessible links inside the app. Website request logs are distinct from app data; re-audit any added website forms, scripts or analytics.
