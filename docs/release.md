# Focus Space release

## Reproducible local package

From a clean checkout on macOS 15 or later with Xcode 26 command-line tools:

```sh
./Scripts/release-check.sh
```

This runs the complete test suite, performs a release build, creates `.build/Focus Space.app`, applies an ad-hoc signature, validates its property list and verifies its code signature. `RELEASE_VERSION` and `RELEASE_BUILD` override the bundle versions.

## Developer ID signing and notarisation

Install an Apple-issued `Developer ID Application` certificate, then store App Store Connect credentials once:

```sh
xcrun notarytool store-credentials FocusSpaceNotary \
  --apple-id "APPLE_ID" --team-id "TEAM_ID" --password "APP_SPECIFIC_PASSWORD"
```

Build, sign with the hardened runtime, submit, wait, staple and Gatekeeper-check in one command:

```sh
SIGNING_IDENTITY="Developer ID Application: NAME (TEAM_ID)" \
NOTARY_PROFILE=FocusSpaceNotary \
RELEASE_VERSION=0.1.0 RELEASE_BUILD=1 \
./Scripts/notarize-app.sh
```

The script intentionally refuses an ad-hoc or Apple Development identity: public distribution requires Developer ID signing and valid private notarisation credentials.

## Performance and visual QA

Profile the 180-thought deterministic space without modifying personal data:

```sh
./Scripts/run-app.sh --demo large --quality efficient --performance-hud
```

Repeat with `--window-size compact`, `standard`, and `large`. The compact size is the supported minimum (980 by 650 points). Verify the standard Retina scale plus any attached non-Retina display. The HUD reports sampled frame rate, p95 frame interval, resident memory, launch-to-workspace time, and the latest autosave latency.

The release review also covers the first-run spatial guide, `--demo empty`, `--simulate-loading`, the accessible-list renderer, Reduce Motion, Increase Contrast, and recovery from a corrupt primary JSON file.
