# MyPropertyVisit for iOS

MyPropertyVisit is a new way of experiencing Real Estate with additional feature such as compass for Direction clarity

Native iOS app for property visits, including planned video calling, compass directions, measurements, and offline walkthroughs.

## Repository

Default iOS source repository: https://github.com/1Bullzeye1/MyPropertyVisit

This repository contains only the iOS app. Android is maintained separately in the sibling `MyPropertyVisit-Android` directory and uses its own repository: https://github.com/1Bullzeye1/MyPropertyVisit_android.

## Open and run

1. Open `ios/MyPropertyVisit.xcodeproj` in Xcode.
2. Select the MyPropertyVisit scheme and an iPhone simulator.
3. Press Command-R.

The Xcode project, scheme, target and app display name are MyPropertyVisit. The current offline launch scope includes property records, capture visits, silent walkthroughs, compass photos/video exports, manual shared room dimensions, full-screen photos and individual/batch sharing or Photos saving. Calling and cloud accounts remain outside launch scope. See [launch documentation](docs/launch/README.md) for the current user guide, privacy/support drafts, store copy and release checklist.

## Build

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project ios/MyPropertyVisit.xcodeproj -scheme MyPropertyVisit -sdk iphonesimulator -configuration Debug -derivedDataPath /tmp/MyPropertyVisitDerivedData CODE_SIGNING_ALLOWED=NO build
```

Requires Xcode and iOS 17 or later. The current bundle identifier is `com.infinity-propview.app`; review signing and distribution settings before release.

## UI themes

The app supports System, Light and Dark preferences. Light uses indigo/lavender; Dark uses aubergine/lavender. Palette values live in `ios/MyPropertyVisit/ContentView.swift`; that source is authoritative. Brand artwork uses the supplied house-and-compass mark.
