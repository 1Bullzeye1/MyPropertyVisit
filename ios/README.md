# PropertyLens for iOS

1. Open `Ganesham.xcodeproj` in Xcode.
2. Select the Ganesham scheme and an installed iPhone simulator.
3. Press Run (Command-R).

The app uses SwiftUI and supports iOS 17 and later. Home and property screens are in `Ganesham/ContentView.swift`; recording, compass, playback, and export are in `Ganesham/WalkthroughView.swift`.

For a physical device, select your development team in Signing & Capabilities and use an appropriate bundle identifier.

Command-line build from the repository root:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project ios/Ganesham.xcodeproj -scheme Ganesham -sdk iphonesimulator -configuration Debug -derivedDataPath /tmp/GaneshamDerivedData CODE_SIGNING_ALLOWED=NO build
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

The user has tested and accepted the recording UI, compass, offline playback, and sharing flow on their iPhone. The broader interruption, low-storage, and accuracy checklist above remains to be completed. Simulator and unsigned device builds pass. Three Swift concurrency warnings remain around recorder state, the compass image cache, and the export session; resolving them is the next maintenance task. iPad is configured portrait-only with full-screen requested; physical iPad verification is pending.
