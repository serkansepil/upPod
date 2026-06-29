# Design QA

final result: blocked

Reference images:

- `/Users/sepil/.codex/generated_images/019f0dce-668c-7f30-9887-cb1ec2383e81/ig_071ebe975d300442016a4112cb22d481918d64739141df8023.png`
- `/Users/sepil/.codex/generated_images/019f0dce-668c-7f30-9887-cb1ec2383e81/ig_071ebe975d300442016a41131277948191952bfc2305f20dfa.png`

Implementation target:

- Native macOS SwiftUI menu-bar popover in `Sources/uppod/PopoverContentView.swift`.
- Shared system-language copy helper in `Sources/uppod/L10n.swift`.

Checks completed:

- `swift build` passed.
- `./build.sh` passed and signed `uppod.app`.
- `posture-spine-icon.png` is packaged in `uppod.app/Contents/Resources`.
- The app was relaunched as a single detached `uppod` process.
- Weekly stats remain collapsed by default through `showStats = false`.
- Popover, exercise screens, and weekly chart empty copy now use the shared Turkish/English text helper.

Blocked checks:

- Automated popover opening/capture is not reliable in this environment without driving the macOS menu bar UI.
- Final visual matching needs a manual screenshot of the open menu-bar popover.

Residual risk:

- Minor visual spacing may need one manual screenshot iteration against the selected mock.
