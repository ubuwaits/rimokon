# Rimokon

A native iPhone remote for LG webOS TVs. SwiftUI, iOS 17+, no external dependencies.

## Use

Swipe the trackpad to navigate; longer swipes move through more items. Tap for OK. Enable **Cursor mode** in settings to move the TV pointer with your finger instead.

Buttons provide power, mute, Back, Home, TV settings, volume, and channels. The small circle between power and mute opens Rimokon settings. No motion sensors are used.

The phone and TV must share a local network. Allow local-network access and accept the TV pairing prompt. On first launch, enter the TV’s IPv4 address in the configuration form. Its MAC address is optional and needed only for power on. Both values are stored locally on the phone; no network addresses are bundled with the app. Existing installations retain their saved configuration. Pairing credentials remain in the iOS Keychain and are not included in the repository.

Power uses the TV's reported state, rather than network connectivity, to distinguish on from standby. Wake-on-LAN requires **Mobile TV On / Turn on via Wi-Fi**. Wake uses unicast UDP and depends on the TV retaining network reachability in standby. Wake reliability depends on the TV and network, especially after extended standby.

Communication uses the TV's local WebSocket interface on port 3000. There are no cloud services or analytics. Automatic discovery is not implemented.

## Build and install

Open `Rimokon.xcodeproj`, select your development team under Signing & Capabilities, choose your iPhone, and Run. The bundle identifier remains `is.chad.Remote` to preserve the existing installation and pairing credentials.

```sh
xcodebuild -project Rimokon.xcodeproj -scheme Rimokon -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

`project.yml` is the XcodeGen source. Run `xcodegen generate` after changing it.

## Regression checks

```sh
swiftc Rimokon/TVConfiguration.swift Tests/ConfigurationRegression.swift -o /tmp/rimokon-config && /tmp/rimokon-config
swiftc Rimokon/TrackpadMode.swift Tests/AppModeRegression.swift -o /tmp/rimokon-swipes && /tmp/rimokon-swipes
swiftc Rimokon/TrackpadDelta.swift Tests/TrackpadRegression.swift -o /tmp/rimokon-trackpad && /tmp/rimokon-trackpad
swiftc Rimokon/TVPowerState.swift Tests/PowerRegression.swift -o /tmp/rimokon-power && /tmp/rimokon-power
```

Configuration changes are saved with **Save & connect**; dismissing the form does not change the TV configuration. Pairing keeps the existing Keychain namespace.
