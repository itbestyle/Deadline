# Redloop

Personal iOS app I built and shipped to the App Store.

Redloop is a deadline tracker with Pressure Mode: it shows how urgent your tasks are, not just a flat to-do list. I designed the product, wrote the SwiftUI client, and built the [Go backend](https://github.com/itbestyle/deadlines-api) it syncs with.

**App Store:** [Redloop](https://apps.apple.com/app/redloop/id6770108637)

## What I implemented

- iPhone app — deadlines, Pressure Mode, calendar, widgets, Live Activities, StoreKit subscription
- Apple Watch companion — tasks grouped by pressure, synced from iPhone
- Localization: English, Russian, Italian, Romanian

Stack: Swift, SwiftUI, SwiftData, WidgetKit, StoreKit 2, WatchConnectivity, Firebase Auth.

## How to run

1. Open `DeadlinesApp.xcodeproj` in Xcode 16+.
2. Copy `GoogleService-Info.plist.example` to `GoogleService-Info.plist` and put in your own Firebase iOS app values. That file is not in git.
3. Select your Development Team on the app, widget, and Watch targets.
4. Run the `DeadlinesApp` scheme.

The Watch app is embedded in the iPhone build. After installing on a paired iPhone, add it from the Watch app.

## Backend

Go API I wrote for this app: https://github.com/itbestyle/deadlines-api
