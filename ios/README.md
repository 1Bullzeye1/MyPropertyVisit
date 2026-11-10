# MyPropertyVisit iOS

Native SwiftUI/AVFoundation app. Launch scope is the current offline property-documentation workflow. See [launch documentation](../docs/launch/README.md) for the scope, user guide, privacy/support drafts, store copy and release gates.

## Open and build

Open MyPropertyVisit.xcodeproj, select the MyPropertyVisit scheme and choose a simulator or connected iPhone. Camera and compass acceptance requires a physical device. The project targets iOS 17+ and iPhone/iPad; native video pause/resume requires iOS 18+.

From the repository root:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project ios/MyPropertyVisit.xcodeproj -scheme MyPropertyVisit -sdk iphoneos -configuration Release -derivedDataPath /tmp/MyPropertyVisitRelease CODE_SIGNING_ALLOWED=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES build
```

Unsigned compilation verifies code, not App Store distribution. Bundle identifier com.infinity-propview.app is retained for installed-data continuity. Set distribution signing and a unique upload build through the release process.

## Current features

- Local property records, optional local profile and System/Light/Dark appearance.
- Rear-camera silent video; native pause/resume on iOS 18+; compass photos before recording or while paused; hardware-dependent zoom buttons only.
- Capture visits group media, with property association when launched from a property.
- Full-screen photos and offline video playback; still capture from saved video.
- Manually entered room details in metres/decimal feet, shared by photos assigned to the same room.
- Photo/video sharing, individual and selected/all media saving to Photos, compass retained in exports.

Calling screens remain placeholders in current source. No verified accounts, cloud sync, AR measurements or complete project backup/restore is part of launch. Room dimensions/notes stay in app records and are not automatically burned into exports. See the release checklist for UI cleanup and privacy manifest work still required.

## Storage and verification

Property/profile preferences use UserDefaults/AppStorage. Videos and JSON sidecars use Documents/Walkthroughs; visit metadata uses Documents/CaptureSessions; JPEGs and shared-room metadata use Documents/RoomPhotos. Exports use temporary copies and Apple Photos or the share sheet. iOS device backup behavior is separate from app-managed backup, which is not implemented.

From the repository root, with an iOS simulator booted:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
sh scripts/check-compass.sh
sh scripts/check-camera-zoom.sh
sh scripts/check-capture-sessions.sh
sh scripts/check-room-photos.sh
```

The launch checklist distinguishes prior successful checks from pending physical-device, interruption, large-library and distribution acceptance. Preserve user data during update tests; never clear the user's app simply to fix a launch snapshot or permission issue.
