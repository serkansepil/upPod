# Release Checklist

## Build And Signing

- [ ] Run `swift build`.
- [ ] Run `./build.sh`.
- [ ] Verify `UpPod.app` launches.
- [ ] Sign with `UPPOD_SIGN_IDENTITY`.
- [ ] Notarize with `UPPOD_NOTARIZE=1`.
- [ ] Run `spctl --assess --type execute --verbose UpPod.app`.

## First Launch

- [ ] Clean install with no existing `~/Library/Application Support/uppod/state.json`.
- [ ] Confirm Motion & Fitness permission prompt text appears in the correct language.
- [ ] Deny permission and confirm the popover shows a recovery message.
- [ ] Allow permission and confirm tracking starts after compatible AirPods connect.

## Menu Bar

- [ ] Verify the status icon is readable in light menu bar.
- [ ] Verify the status icon is readable in dark menu bar.
- [ ] Verify color changes for good, slight, poor, and paused states.
- [ ] Confirm popover opens and closes reliably.

## Posture Flow

- [ ] AirPods disconnected state is clear.
- [ ] Calibration-needed state is clear.
- [ ] Calibration completes and persists after restart.
- [ ] Daily score and time distribution update during real use.
- [ ] Last 7 days is collapsed by default and expands cleanly.

## Exercise Flow

- [ ] Exercise window opens from the popover.
- [ ] Each exercise uses the correct image and instruction.
- [ ] Repetition and hold counts advance.
- [ ] Stop, skip, and completion screens work.
- [ ] Results persist after session completion.

## Localization

- [ ] Turkish UI copy is coherent.
- [ ] English UI copy is coherent.
- [ ] `InfoPlist.strings` is bundled for `en` and `tr`.

## Data And Privacy

- [ ] `state.json` is created only under Application Support.
- [ ] No network access is required for posture tracking.
- [ ] Privacy copy matches `PRIVACY.md`.

## Deferred

- [ ] Add automated tests for persistence, scoring, calibration restore, state transitions, and exercise counting.
