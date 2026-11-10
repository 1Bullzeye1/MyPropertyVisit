# Launch scope — iOS 1.0

Baseline date: 10 November 2026. Price: USD 4.99 paid download, subject to store regional pricing. Target audience: buyers, sellers and brokers who document property visits.

## Included

- Save a property name, land/flat/building type and manually entered location/address locally.
- Rear-camera silent walkthrough recordings; live magnetic compass and bearing readings.
- Export video with a rendered compass and degree readout. Preserve unavailable readings rather than inventing them.
- Take compass-stamped photos directly, or capture a still from a saved walkthrough.
- Hardware-dependent zoom preset buttons. No zoom slider or pinch gesture is promised.
- Capture sessions to group photos and videos. Associate captures with a property when launched from that property.
- Native pause/resume and still capture while paused on iOS 18 or later. On iOS 17, use separate recordings and photos between recordings.
- Full-screen photo viewing and video playback.
- Human-entered room names/categories, notes, length/width/optional height; metres or decimal feet. Calculated rectangular area from entered length and width.
- Photos assigned to the same room share room details. A category alone does not mean every bedroom is the same room.
- Individual and multi-item photo/video sharing and save-to-Photos. Select all in a visit to export a session.
- Optional local profile and System/Light/Dark appearance.

## Outside launch scope

Live calls, joining calls with codes, contact sync, verified accounts, cloud backup, cross-device or team sync, AR/automatic measurements, automatic room recognition, floor plans, PDF property reports, complete project backup/restore, subscriptions and website checkout.

Calling screens remain placeholders in current source. They must be hidden or relabelled accurately before store submission; this documentation does not claim they were removed. No new feature is required merely to align the current UI with this scope.

## Limitations to disclose

- Compass is magnetic and sensor dependent. Nearby metal/magnets can affect readings; no survey/navigation accuracy guarantee is made.
- Room dimensions are supplied by the user. Exported JPEG/video files retain the compass, but editable dimensions, notes, room assignments and property/session relationships are not automatically burned into those exports.
- Exporting media is not a full MyPropertyVisit backup. The app has no project restore flow.
- Core data is in the local app container. iOS device backup settings may include it; the app neither manages nor guarantees that backup. Uninstalling, losing or erasing a device can cause data loss.
- Clearing a local profile keeps property/media records. Deleting a property record does not establish deletion of associated photos/videos.
- Photo deletion exists. No dedicated video/session deletion UI was found in this source review; do not tell users it exists.
- Zoom, camera combinations and compass availability vary by hardware.

## Technical baseline

Bundle identifier: com.infinity-propview.app. Marketing version currently 1.0, build currently 2; assign a unique build number before upload. Deployment target iOS 17.0. Project targets iPhone and iPad; final iPad layout/orientation acceptance remains required.

Reference commit ecbc91a is the prior checkpoint, not a commit of all current launch changes. Current release source must be captured after outstanding changes are reviewed.
