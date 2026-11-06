# PropertyLens for iOS

1. Open `PropertyLens.xcodeproj` in Xcode.
2. Select the PropertyLens scheme and an installed iPhone simulator.
3. Press Run (Command-R).

The app uses SwiftUI and supports iOS 17 and later. Home and property screens are in `PropertyLens/ContentView.swift`; recording, compass, playback, and export are in `PropertyLens/WalkthroughView.swift`.

For a physical device, select your development team in Signing & Capabilities and use an appropriate bundle identifier.

Command-line build from the repository root:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project ios/PropertyLens.xcodeproj -scheme PropertyLens -sdk iphonesimulator -configuration Debug -derivedDataPath /tmp/PropertyLensDerivedData CODE_SIGNING_ALLOWED=NO build
```

If Xcode reports an unaccepted license, open Xcode and complete its license and first-launch setup before building. Subsequent simulator and unsigned physical-device builds have passed.

## Offline walkthrough recorder

Open **Record walkthrough** on Home or inside a saved property's Tour tools. The property-specific entry links recordings to that property's UUID. The recorder’s Saved button shows all walkthroughs when opened from Home, or the selected property’s walkthroughs when opened from a property.

- Requires a physical iPhone with camera access. The simulator cannot validate camera recording or magnetic compass readings.
- Records rear-camera video only, without microphone audio or application controls.
- Hold the phone upright in portrait. Compass reports the phone top-edge magnetic bearing, not a calibrated optical camera azimuth or true north.
- Movie files and timestamped compass JSON are saved in the app's Documents/Walkthroughs directory. The app library discovers completed movie/JSON pairs after restart.
- In-app playback displays available compass samples. Use Share video with compass during playback to export a copy with timestamped magnetic bearings embedded into its frames. The original remains unchanged. The compact dial has N/E/S/W labels and a degree readout. Missing or stale samples show a slash and a dash.
- No video calling, uploading, automatic face blurring, or recording deletion UI is implemented yet. Deleting the app removes its local recordings.

### Physical-device acceptance checklist

1. Deny camera access: see explanatory text and a disabled recording button. Enable permission in Settings and reopen the screen.
2. Record a short portrait walkthrough, rotate around magnetic north, stop, and play it offline. Confirm no audio, participant UI, or app controls are recorded.
3. Scrub playback: direction readings should follow recorded timestamps; missing readings must not show invented values.
4. Force-quit after a successful save and reopen: the recording remains playable. Open from the same property and confirm association.
5. Open playback, return to the recorder, and confirm camera preview restarts.
6. Background or interrupt recording: verify it stops and saves any successfully finalized movie.
7. Test on a device with low storage and inspect failure feedback. Check compass behaviour away from magnets and metal; accuracy is device/environment dependent.

### Compass export acceptance checklist

Record while changing direction, stop, open playback, and choose **Share video with compass**. Wait for preparation, then save the result to Files or send it to another device. Play it in a standard video player and scrub through the recording. Check that the top-left bearing follows the same timestamps as in-app playback and is readable in the saved orientation. With no heading samples, the dial must show an unavailable slash and dash instead of a bearing. Export requires free space for a second video; failures show an alert rather than sharing the original without its overlay.

## Baseline verification and follow-up

The user has tested and accepted the recording UI, compass, offline playback, and sharing flow on their iPhone. The broader interruption, low-storage, and accuracy checklist above remains to be completed. Simulator and unsigned device builds pass. The recorder, cache, and export-session concurrency warnings have been resolved. UI state is main-actor isolated; capture operations belong to a dedicated camera actor. The only unchecked Sendable bridges are the preview-session reference (AVFoundation preview binding only) and an explicitly locked cache of immutable CIImages. Export-session access stays on the main actor. Complete concurrency checking is enabled in Debug and Release. iPad is configured portrait-only with full-screen requested; physical iPad verification is pending.

## Stability regression checks

With an iOS simulator booted, run from the repository root:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer scripts/check-compass.sh
```

This compiles the actual compass renderer and locked cache into a simulator check executable. It checks 2,000 concurrent cache operations, all four cardinal headings and unavailable rendering, and timestamped compass metadata encoding/decoding. Optionally pass a simulator UDID as the first argument.

Simulator and unsigned device builds pass with complete Swift concurrency checking. The App Intents metadata tool may emit an unrelated warning because this app has no App Intents integration. After the actor refactor, repeat recording, stop/save, reopening preview after playback, interruption/backgrounding and compass sharing on a physical iPhone before merging to main. These physical-device regression checks have not been run by the agent.

## Settings

Open the gear button on Home. Display offers System, Light and Dark; the selected appearance persists across launches. Account offers an editable device-local name, optional email and Buyer/Seller/Broker role, with a clear-profile action that preserves property records and walkthroughs. This is not online authentication: sign-in, account switching and cloud sync remain unimplemented.


## Room photos and manual dimensions

Open a saved walkthrough, pause at a useful frame and tap **Capture room photo**. Choose the room/area type and name, optionally enter length and width together, height and notes, then save. Dimensions use metres or decimal feet. Area assumes a rectangle. Room identity and measurements are supplied by the user.

Cards are stored offline as JPEG and JSON under Documents/RoomPhotos, linked to the source video timestamp and property when available. Browse from Home, the property details, or the source walkthrough. Edit details later without changing the original video. This feature does not embed dimensions into shared videos or automatically identify rooms. Photos are extracted with the source video's orientation applied.

Run `sh scripts/check-room-photos.sh` on a booted simulator to check persistence, edits, filtering, validation and deletion. Device acceptance: capture portrait video frames, save a card without dimensions, reopen the app, edit dimensions, switch units and confirm the photo and source link remain intact.


### Direct photos and shared rooms

The Photo button beside Record saves a still image immediately as an uncategorised card. Photo capture is enabled before recording and while recording is paused. Home → Photos & videos opens the library without starting the camera. Saved properties → property → Property photos & videos filters media for that property.

Choose Use an existing room’s details when editing a photo. Category, name, dimensions, units and notes are shared by photos assigned to that room; images and source timestamps remain separate. Use Bedroom 1/Bedroom 2 for different rooms, or Separate this photo into a new room to detach one. Sharing is limited to a property; unassigned video captures share within their video and direct photos within the unassigned camera collection.

Legacy photos migrate to an atomic rooms-v2.json index on first access, retaining JPEGs and original sidecars. Same-property/type/name photos initially share the latest edited details. Each save writes room changes in one atomic index replacement. Direct camera capture requires physical-iPhone verification.


### Camera zoom

Use the slider or tap a zoom shortcut before or during recording. The rear virtual triple/dual camera is preferred when available, falling back to the wide camera. Displayed factors use Apple's display multiplier (or the wide-lens switch-over factor on iOS 17). The initial view is 1×. Shortcuts reflect available camera switch-over factors plus a 2× zoom option when supported; intermediate factors may be digital crops. iOS chooses the physical lens based on its capture conditions. Maximum UI zoom is capped at 10× unless a native lens switch-over is higher, and always constrained to the current device limits. Photos use the same selected zoom.

Run `sh scripts/check-camera-zoom.sh` with a booted simulator for bounds and preset checks. Physical-device acceptance: verify the initial 1× field of view; test available wide/telephoto shortcuts and slider; record continuously while changing zoom; replay and export the video with compass; take a zoomed photo. Hardware switching and image quality cannot be verified with the simulator.


### Visit sessions and video pause

The first photo or video starts a visit session automatically. Further captures use that session until End session or leaving the recorder. Home → Photos & videos → Sessions opens a visit with its photo collection and videos. Sessions also appear in the property's media library. Older media remain available in the all-media lists; no previous visit membership is invented.

On iOS 18 and later, Pause freezes writing to the current video, enables Photo, and Resume continues in the same video file. Stop also works while paused. Camera preview stays live. Compass timestamps are anchored to recorded movie duration on resume; paused wall time is excluded. iOS 17 still supports ordinary record/stop and photos between videos; the native Pause button requires iOS 18. Background/interruption stops and saves the current recording, including when paused. Pinch zoom has been removed; slider and zoom shortcuts remain.

Run `sh scripts/check-capture-sessions.sh` for repeated-pause timeline, session persistence/filtering/end and legacy-video compatibility checks, plus `sh scripts/check-room-photos.sh` for photo session filtering and edit retention. On a physical iPhone: record → Pause → take multiple photos → Resume → Stop, then verify one playable video with no paused gap, aligned compass after each resume, and all captures in one session. End session and confirm the next capture is in a separate visit. Stop while paused and repeat the background/interruption checks.
