# Contributing to LibreArm (iOS)

Thank you for your interest in contributing to LibreArm! This project keeps QardioArm blood pressure monitors functional after Qardio shut down. Every contribution helps thousands of users continue monitoring their health.

## Getting Started

### Prerequisites

- Xcode 15 or later
- iOS 16+ device (BLE is not available in the simulator)
- A QardioArm blood pressure monitor for testing
- Apple ID (free developer account is sufficient for device testing)

### Building

1. Clone the repository
2. Open `LibreArm.xcodeproj` in Xcode
3. Select your development team under Signing & Capabilities
4. Build and run on a physical iOS device

## How to Contribute

### Reporting Bugs

- Open a GitHub issue with a clear title and description
- Include your iOS version, device model, and QardioArm generation (if known)
- Describe what you expected vs what happened
- Include steps to reproduce if possible

### Suggesting Features

- Open a GitHub issue describing the feature and its value to users
- Check existing issues first to avoid duplicates
- For larger features, discuss the approach in an issue before writing code

### Submitting Pull Requests

1. Fork the repository and create a feature branch from `main`
2. Keep PRs focused — one feature or fix per PR
3. Test on a physical device with a QardioArm
4. Update the README if your change adds user-facing features
5. Open a PR with a clear description of what changed and why

### What We're Looking For

Areas where contributions are especially welcome:

- **UI improvements** — Accessibility, dark mode, layout refinements
- **Bluetooth stability** — Connection reliability, error recovery, edge cases
- **Documentation** — README improvements, code comments for complex logic
- **New features** — Local history, trend charts, data export, measurement reminders
- **Testing** — Unit tests for SFLOAT parsing, validation logic, and data models

## Code Style

LibreArm follows standard Swift conventions. Please match the existing patterns:

### Naming

- **Types**: PascalCase (`BPClient`, `BPReading`, `ContentView`)
- **Variables/functions**: camelCase (`lastReading`, `startConnect`, `isValidReading`)
- **Enum cases**: lowerCamelCase (`single`, `average3`)
- **Private constants**: camelCase (`bpsService`, `startCommand`)

### Organization

- Use `// MARK: - Section Name` to organize code within files
- Use `final class` for non-subclassable classes
- Use `private` for implementation details
- Use `guard` for early returns and validation

### Patterns

- **State**: `@Published` properties on `ObservableObject` classes
- **Persistence**: `@AppStorage` for user preferences
- **Errors**: `guard` + early return (no try/catch unless calling throwing APIs)
- **Async**: `DispatchQueue.main.async` for UI updates from BLE callbacks
- **Callbacks**: Optional closures (`var onFinalReading: ((BPReading) -> Void)?`)

### Formatting

- 4-space indentation
- Opening braces on the same line
- Generally keep lines under 120 characters
- One blank line between functions

### Dependencies

- **Prefer native frameworks** — CoreBluetooth, HealthKit, SwiftUI, UserNotifications
- Do not add third-party dependencies without discussion in an issue first

## Architecture

```
LibreArm/
├── App/
│   ├── LibreArmApp.swift          # App entry point, injects environment objects
│   ├── ContentView.swift          # Main screen UI
│   └── HypertensionGraphView.swift # Blood pressure classification chart
└── Core/
    ├── BPClient.swift             # BLE connection, measurement protocol, validation
    └── Health.swift               # HealthKit write integration
```

- **BPClient** is the core engine — it manages BLE, measurement state, battery monitoring, and reading validation
- **Health** is a thin wrapper around HealthKit for writing BP and heart rate data
- **ContentView** observes BPClient state and renders the UI
- **HypertensionGraphView** is a pure view component driven by systolic/diastolic inputs

## Testing

There are currently no automated tests. If you add tests:

- Place unit tests in a `LibreArmTests/` directory
- Test SFLOAT parsing with known byte sequences
- Test validation logic with boundary values
- BLE communication requires a real device and cannot be unit tested easily

## Questions?

Open an issue or reach out. We appreciate your help keeping QardioArm devices alive.
