# PropertyLens for iOS

PropertyLens is a new way of experiencing Real Estate with additional feature such as compass for Direction clarity

Native iOS app for property visits, including planned video calling, compass directions, measurements, and offline walkthroughs.

## Repository

Default iOS source repository: https://github.com/1Bullzeye1/PropertyLens

This repository contains only the iOS app. Android is maintained separately in the sibling `PropertyLens-Android` directory and uses its own repository: https://github.com/1Bullzeye1/PropertyLens_android.

## Open and run

1. Open `ios/PropertyLens.xcodeproj` in Xcode.
2. Select the PropertyLens scheme and an iPhone simulator.
3. Press Command-R.

The Xcode project, scheme, target, and app display name are PropertyLens. The prototype includes locally saved property details, offline rear-camera walkthrough recording, a live compass, and shared video exports with a compact compass and degree overlay. Call screens remain placeholders; live calling and measurement capture are not connected yet.

## Build

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project ios/PropertyLens.xcodeproj -scheme PropertyLens -sdk iphonesimulator -configuration Debug -derivedDataPath /tmp/PropertyLensDerivedData CODE_SIGNING_ALLOWED=NO build
```

Requires Xcode and iOS 17 or later. The current bundle identifier is `com.infinity-propview.app`; review signing and distribution settings before release.

## Approved UI themes

The approved home-screen layout supports two independent palettes, defined centrally in `ios/PropertyLens/ContentView.swift`.

| Role | Light | Dark |
| --- | --- | --- |
| Brand / navigation | `#6250C8` | `#94C7ED` |
| Primary action | `#6250C8` | `#295C7C` |
| Main text | `#25213D` | `#E9EFF5` |
| Background | `#F6F5FB` | `#111820` |
| Card surface | `#FFFFFF` | `#1B2632` |
| Card border | `#E8E4F3` | `#334352` |
| Icon background | `#EEEAFB` | `#293B4A` |
| Secondary accent | `#BF4257` | `#E6BC92` |
| Hero gradient | `#282148` → `#514184` | `#233A4B` → `#31566A` |

Follow the device appearance automatically. Preserve these approved palettes when adding screens unless a theme change is requested.
