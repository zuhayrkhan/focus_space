# Milestone 9 — Delight and release hardening

Status: complete for personal/internal use on the owner's Macs.

Distribution decision: Focus Space is not currently intended for public distribution. Its release artifact is therefore a reproducible, locally built and ad-hoc signed app. Developer ID signing and Apple notarisation remain implemented as a dormant future distribution path, not an acceptance blocker.

## Experience system

- Camera, gravity, fades and springs now draw from one calm motion vocabulary.
- Selection and depth each have a short synthesized audio cue. Sound is off by default and can be enabled under Workspace guides → Sound & motion.
- The audio envelope is deliberately low amplitude and tested for a fast, clean decay.
- Empty and loading spaces have purpose-built quiet states; first launch retains the four-step spatial guide and deterministic starter constellation. Persistence failures remain explicit and actionable through the storage-details flow.

## Performance

- `--demo large` provides a deterministic 180-thought stress space.
- `--quality efficient|balanced|cinematic` pins a rendering profile for comparable runs.
- `--performance-hud` samples frame rate, p95 frame interval, resident memory, launch-to-workspace time and autosave latency.
- `--window-size compact|standard|large` supports repeatable window-size checks, with 980 by 650 points as the minimum.

## Release path

- `Scripts/release-check.sh` is the clean-checkout release gate: tests, release build, app assembly, plist validation and strict signature verification.
- `Scripts/package-app.sh` supports ad-hoc local builds and hardened-runtime Developer ID signing with explicit version/build overrides.
- `Scripts/notarize-app.sh` validates the distribution identity, submits with `notarytool`, waits, staples and performs a Gatekeeper assessment.
- Full operator instructions are in [release.md](release.md).

## Acceptance evidence

- 57 automated tests pass, including schema migration, atomic recovery, autosave latency, keyboard/VoiceOver semantics, deterministic fixtures and renderer reconciliation.
- The signed release app was reviewed at the compact, standard and large requested window sizes on the built-in 3024 by 1964 Retina display. First-run, empty, loading, dense, high-contrast and accessible-list states were included across Milestones 7–9.
- The 32-node dense fixture reported 210–216 MB resident memory, 1.7 seconds from process initialization to the first measured workspace frame, and a 34–44 fps main-thread cadence while the accessibility screenshot harness was actively capturing it. This capture-heavy figure is diagnostic, not a renderer-frame benchmark.
- A capture-free 180-node efficient-quality run settled at 358 MB resident memory and approximately 32% CPU on the Apple M5 Max test Mac after 15 seconds, with interaction remaining responsive.
- The local release gate assembles and verifies the ad-hoc signed application successfully.
- The agreed release baseline for this personal scope is the owner's current MacBook Pro (Apple M5 Max, 128 GB) on its built-in Retina display. A second personally owned Mac can build the same artifact from a clean checkout; wider hardware certification is deliberately outside this release scope.
- Public notarisation was not performed because no public distribution is planned. If that decision changes, the checked-in Developer ID/notarytool path becomes a new release gate.
