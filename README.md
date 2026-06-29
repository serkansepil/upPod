# UpPod

UpPod is a macOS menu bar app that uses compatible AirPods motion data to track head tilt, estimate neck posture strain, and guide short neck exercises. Data is stored locally on the Mac.

## Requirements

- macOS 14 or newer
- Compatible AirPods with headphone motion support
- Motion & Fitness permission

## Build

```bash
./build.sh
open UpPod.app
```

`build.sh` creates `UpPod.app`, copies bundled resources, and signs the app.

By default it uses ad-hoc signing for local builds. For Developer ID signing:

```bash
UPPOD_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./build.sh
```

For notarization:

```bash
UPPOD_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
UPPOD_NOTARIZE=1 \
UPPOD_NOTARY_APPLE_ID="apple-id@example.com" \
UPPOD_NOTARY_PASSWORD="app-specific-password" \
UPPOD_TEAM_ID="TEAMID" \
./build.sh
```

Or store notarization credentials once in Keychain and reuse the profile:

```bash
xcrun notarytool store-credentials uppod-ecma \
  --apple-id "apple-id@example.com" \
  --team-id "TEAMID" \
  --password "app-specific-password"

UPPOD_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
UPPOD_NOTARIZE=1 \
UPPOD_NOTARY_PROFILE=uppod-ecma \
./build.sh
```

Create a DMG after building:

```bash
brew install create-dmg
./package-dmg.sh
```

For a signed and notarized DMG:

```bash
UPPOD_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
UPPOD_NOTARIZE=1 \
UPPOD_NOTARY_PROFILE=uppod-ecma \
./package-dmg.sh
```

## Debug Builds

Internal flags are honored only in SwiftPM debug builds.

```bash
UPPOD_MOCK=1 swift run
UPPOD_MOCK=1 UPPOD_DEBUG=1 swift run
UPPOD_MOCK=1 UPPOD_MOCK_EXERCISE=1 swift run
```

Release builds ignore these flags.

## Data

UpPod stores calibration, sensitivity, daily posture summaries, and exercise session summaries in:

```text
~/Library/Application Support/uppod/state.json
```

No posture data is sent to a server by this app.

## Current Production Status

Ready for local signed builds and manual QA. Before public distribution:

- Sign with a Developer ID certificate.
- Notarize and staple the app.
- Complete the manual release checklist in `RELEASE_CHECKLIST.md`.
- Add automated tests in the final hardening pass.

## Architecture

```text
Motion.swift             AirPods or mock motion source
Pipeline.swift           gravity-fused flexion, smoothing, gate, classifier
Strain.swift             neck load and strain estimate
Scoring.swift            daily dose and posture score
Persistence.swift        local JSON persistence
PostureEngine.swift      app state orchestration
StatusBar.swift          NSStatusItem and popover host
PopoverContentView.swift menu bar popover UI
ExerciseEngine.swift     exercise session logic
ExerciseSessionView.swift exercise UI
```
