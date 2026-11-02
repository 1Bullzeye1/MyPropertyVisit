# Ganesham for iOS

1. Open `Ganesham.xcodeproj` in Xcode.
2. Select the Ganesham scheme and an installed iPhone simulator.
3. Press Run (Command-R).

The app uses SwiftUI and supports iOS 17 and later. Edit `Ganesham/ContentView.swift` to change the welcome screen.

For a physical device, select your development team in Signing & Capabilities and use an appropriate bundle identifier.

Command-line build from the repository root:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project ios/Ganesham.xcodeproj -scheme Ganesham -sdk iphonesimulator -configuration Debug -derivedDataPath /tmp/GaneshamDerivedData CODE_SIGNING_ALLOWED=NO build
```

If Xcode reports an unaccepted license, open Xcode and complete its license and first-launch setup before building. The initial command-line build on this Mac stopped at this prerequisite; compilation is not yet verified.
