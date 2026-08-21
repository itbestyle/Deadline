# Redloop

iOS app for deadlines and time pressure. SwiftUI, SwiftData, WidgetKit, Live Activities, StoreKit 2, and an Apple Watch companion.

## What’s in the repo

- iPhone app (`DeadlinesApp`) — tasks, Pressure Mode, widgets, calendar, localization (en/ru/it/ro)
- Watch app (`RedloopWatch Watch App`) — companion list synced from iPhone
- Widget extension (`DeadlineWidgetExtension`)

## Run locally

1. Open `DeadlinesApp.xcodeproj` in Xcode 16+.
2. Copy `GoogleService-Info.plist.example` to `GoogleService-Info.plist` in the project root and fill in your Firebase iOS app values. That file is intentionally not in git.
3. Select your Development Team on the `DeadlinesApp`, `DeadlineWidgetExtension`, and `RedloopWatch Watch App` targets.
4. Build and run the `DeadlinesApp` scheme on a device or simulator.

The Watch app is embedded in the iPhone app (`Watch/`). Install it from the Watch app on iPhone after running `DeadlinesApp` on a paired device.
