# Rimokon

A minimal iPhone remote for LG webOS TVs. iOS 17+, no external dependencies.

<img src="docs/rimokon.png" alt="Rimokon’s dark remote interface with a large touchpad and power, mute, navigation, volume, and channel controls" width="320">

## Setup

1. Connect your iPhone and TV to the same network.
2. Enter the TV’s IP address in Rimokon settings (the small circle between power and mute).
3. Allow local-network access and accept pairing on the TV. Rimokon retrieves the MAC address automatically.

For power-on support, enable **Mobile TV On / Turn on via Wi-Fi** on the TV. Wake-up depends on the TV remaining reachable in standby. A manual MAC override is available in settings.

## Controls

Swipe to navigate; longer swipes move through more items. Tap for OK. Enable **Cursor mode** in settings for direct pointer control.

## Development

Open `Rimokon.xcodeproj`, select your signing team and iPhone, and Run. Run `xcodegen generate` after editing `project.yml`.

Standalone regression checks live in `Tests/`; compile each with its corresponding source files. For example:

```sh
swiftc Rimokon/TVStates.swift Tests/RecoveryRegression.swift -o /tmp/rimokon-recovery
/tmp/rimokon-recovery
```
