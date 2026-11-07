# Ghaf

Ghaf is a personal budgeting application for iOS.

It automatically records bank transactions through Apple Shortcuts
and categorizes spending locally on the device.

## Features

- Automatic bank message parsing
- Transaction categorization
- Daily spending limits
- Category budgets
- Needs Review inbox
- Monthly insights
- Local JSON backup
- No accounts, analytics, or external servers

## Technology

- SwiftUI
- SwiftData
- Swift Charts
- App Intents
- Swift Package Manager
- XcodeGen
- GitHub Actions

Minimum iOS version: 17.0

Bundle identifier: com.ghaf.app

## Repository Structure

- Ghaf: iOS application
- Packages/GhafCore: transaction parser and unit tests
- .github/workflows: CI build automation
- project.yml: XcodeGen configuration

## Building

Ghaf is built using GitHub Actions.

No local Mac or Xcode installation is required.

The workflow:

1. Checks out the repository.
2. Selects Xcode 16.4.
3. Installs XcodeGen.
4. Generates Ghaf.xcodeproj.
5. Runs GhafCore unit tests.
6. Builds the iOS application without signing.
7. Creates an unsigned archive.
8. Packages Ghaf.ipa.
9. Uploads the IPA as a GitHub artifact.

## Running the Workflow

1. Open the repository on GitHub.
2. Select Actions.
3. Select Build Ghaf iOS.
4. Click Run workflow.
5. Select the main branch.
6. Confirm Run workflow.

Commits pushed to main also trigger the workflow automatically.

## Downloading the IPA

When a workflow completes:

1. Open Actions.
2. Select the completed Build Ghaf iOS run.
3. Scroll down to Artifacts.
4. Download Ghaf-unsigned-ipa.
5. Extract the downloaded ZIP.
6. Locate Ghaf.ipa.

Build artifacts are retained for 14 days.

## Signing

The generated IPA is unsigned.

Use FlareStore or another compatible signing service to sign it.

Required signing materials:

- P12 certificate
- P12 password, if protected
- Mobile provisioning profile

The provisioning profile must be compatible with the app bundle identifier
and the target device.

Never commit signing materials to this repository.

## Apple Shortcuts

After the App Intent implementation is added, Ghaf will expose
the Log Bank Message action in Apple Shortcuts.

SMS automation:

1. Open Shortcuts.
2. Create a Personal Automation.
3. Select Message.
4. Configure the bank sender.
5. Add Log Bank Message.
6. Pass the incoming Message variable.
7. Pass the sender name when available.
8. Configure automatic execution where supported.

For bank application notifications, use a Notification automation
where the installed iOS version supports it and the notification
content is available as an automation input.

The completed App Intent implementation and onboarding will provide
the final configuration instructions.

## Privacy

All financial records are stored locally using SwiftData.

Ghaf does not require an online account or external financial server.
Bank messages are processed on the device.

No certificates, passwords, provisioning profiles, or real bank
messages should be committed to the repository.
