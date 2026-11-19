# Ghaf

Ghaf is a personal finance and budgeting app for iPhone, designed around multiple accounts, cash wallets, transaction capture and spending clarity.

## Current capabilities

- Multiple cash and bank accounts, each with its own currency and opening balance
- Account balances calculated from assigned transactions
- Daily and category budgets
- Salary-day reminders and deposit confirmation
- Bank-message parsing through an App Intent exposed to Apple Shortcuts
- Local merchant categorization with learned user corrections
- GCC bank support contacts for 26 institutions across six countries
- Transaction review, editing and deletion
- Monthly insights
- Local JSON backup and restore (currently unencrypted)
- Manual export through Files, including iCloud Drive or Google Drive when installed
- English and Arabic interface foundations
- Ghaf app icon and reusable brand mark assets
- Seven UAE city-inspired themes
- Face ID / device-passcode lock

Some requested capabilities are still in development. Voice capture currently uses Apple's speech recognition framework and a rule-based transaction splitter; it is not a generative AI financial assistant. Sign in with Apple, Google Drive/iCloud backup and sync, full merchant enrichment and final App Store signing are not yet complete.

## Technology

- SwiftUI
- SwiftData
- Swift Charts
- Speech
- AVFoundation
- App Intents
- Swift Package Manager
- XcodeGen
- GitHub Actions with a self-hosted macOS runner

Minimum iOS version: 17.0

Bundle identifier: `com.ghaf.app`

## Repository structure

- `Ghaf`: iOS application
- `Packages/GhafCore`: bank-message parser and unit tests
- `.github/workflows`: manual build workflow
- `project.yml`: XcodeGen configuration

## Build runner

The build workflow is manual-only and targets an Apple Silicon Mac registered as a self-hosted GitHub Actions runner. This avoids consuming GitHub-hosted Actions minutes.

### One-time Mac setup

1. Open the repository Settings → Actions → Runners.
2. Select **New self-hosted runner**.
3. Choose **macOS** and **ARM64**.
4. Follow GitHub's generated download and configuration commands in Terminal.
5. Start the runner from its installation directory with:

   ```bash
   ./run.sh
   ```

6. Keep the runner process running while a build is queued or executing. GitHub should show the runner as **Idle** when it is ready.

Select a valid Xcode installation on the Mac before starting a build:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -version
xcrun --sdk iphoneos --show-sdk-version
```

Install XcodeGen if it is not already available:

```bash
brew install xcodegen
```

The workflow uses the Xcode selected by `xcode-select`; it does not require a specific Xcode application folder name.

### Run a build

1. Open the repository's **Actions** tab.
2. Select **Build Ghaf iOS**.
3. Click **Run workflow** and choose `main`.
4. Confirm **Run workflow**.

Pushing commits does not start a build. Group development changes and run the workflow at deliberate checkpoints.

### Workflow outputs

A successful run currently produces:

- `Ghaf-unsigned-ipa`: unsigned archive packaged as an IPA
- `Ghaf-iPhone-17-preview`: simulator screenshot (uses another available iPhone simulator if iPhone 17 is not installed)

On failure, diagnostic logs are uploaded as an artifact. Build artifacts are retained for 14 days.

## Signing and App Store release

The current IPA is **unsigned**. It is a packaging/checkpoint artifact, not a final installable or App Store-submittable IPA.

A signed release requires:

- An Apple Developer Program team
- The correct App ID / bundle identifier
- An Apple Distribution certificate and private key
- An App Store provisioning profile
- Xcode archive export settings configured for App Store distribution
- App Store Connect app record, privacy details, screenshots and review metadata

Signing credentials and provisioning profiles must never be committed to this repository. They should be installed securely on the self-hosted Mac or supplied through protected GitHub secrets.

## Apple Shortcuts

Ghaf exposes the **Capture Bank Alert** App Intent. A Personal Automation can pass the incoming bank message text and sender to this action. iOS controls which automation triggers can run automatically and which message contents are available.

The app cannot independently read every other app's notifications or bypass iOS privacy restrictions.

## Privacy

Financial records are stored locally using SwiftData. The current app does not require a Ghaf online account or external financial server. Bank messages passed to the App Intent are parsed on-device. Voice capture requests microphone and speech-recognition access only when the user starts recording; the transcript and proposed transactions remain editable before saving.

Cloud backup and sign-in are planned features and are not currently implemented.

Never commit certificates, passwords, provisioning profiles, API keys or real bank messages to this repository.
