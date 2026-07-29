# Usability milestone U5 — measured scale and interaction feel

Status: implementation and measured release gate complete on 29 July 2026; final physical-trackpad acceptance remains a short hands-on check.

U5 turns the provisional scale expectations from the usability review into repeatable measurements on the target Mac. RealityKit work and accessibility projection are measured independently, and the large spatial workspace no longer publishes hundreds of off-context accessibility elements on every update.

## Instrumentation

Focus Space emits `OSSignposter` intervals in the `com.zuhayrkhan.FocusSpace` / `MeasuredExperience` category for:

- launch to first interactive workspace update
- scene-snapshot derivation
- renderer reconciliation
- relationship reconciliation
- accessibility representation
- Arrange
- search framing
- Option-drag preview

The release harness records the same interval durations as count, mean, p50, p95, and maximum values in JSON. This makes the automated report useful in CI while retaining native signposts for Instruments.

## Reproducible matrix

Run:

```sh
./Scripts/run-performance-matrix.sh
```

The command packages and ad-hoc signs the exact app, then exercises the 32-, 65-, and 180-thought fixtures at compact, standard, and large content sizes. Reports and launch logs are written to `.build/performance-u5/`.

The compact window resolves to `980 × 702` on this build because the native toolbar and supported minimum workspace height take precedence over the requested `980 × 650`. Standard and large resolve exactly to `1240 × 780` and `1260 × 820`.

Baseline captured on 29 July 2026:

| Fixture | Size | Interactive | Presentation | Live preview | Search | Arrange | Spatial accessibility |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 32 | compact | 760 ms | 60.0 fps | 57.2 fps | 0.23 ms | 0.96 ms | 32 |
| 32 | standard | 690 ms | 59.3 fps | 57.9 fps | 0.20 ms | 0.56 ms | 32 |
| 32 | large | 737 ms | 59.7 fps | 55.9 fps | 0.25 ms | 0.68 ms | 32 |
| 65 | compact | 638 ms | 58.7 fps | 57.7 fps | 0.63 ms | 9.54 ms | 5 of 65 |
| 65 | standard | 637 ms | 59.0 fps | 56.6 fps | 0.36 ms | 7.86 ms | 5 of 65 |
| 65 | large | 643 ms | 58.7 fps | 61.3 fps | 0.37 ms | 8.38 ms | 5 of 65 |
| 180 | compact | 934 ms | 55.7 fps | 54.5 fps | 0.59 ms | 20.88 ms | 18 of 180 |
| 180 | standard | 931 ms | 55.1 fps | 58.4 fps | 0.59 ms | 17.42 ms | 18 of 180 |
| 180 | large | 936 ms | 56.0 fps | 56.5 fps | 0.57 ms | 22.85 ms | 18 of 180 |

The confirmed target-Mac gates are:

- 32 and 65 thoughts: under 1.1 seconds from application initialisation to interactive
- 180 thoughts: under 2 seconds
- presentation and direct preview: at least 30 fps
- search framing: under 100 ms
- Arrange: under 250 ms; a progress surface is not yet warranted at the measured 20 ms maximum
- spatial accessibility: at most 48 context-relevant thoughts

## Accessibility at scale

Maps with at most 48 thoughts retain their complete spatial accessibility representation. Larger maps publish the selected family, direct context, current branch, and visible presentation levels in that order, up to 48 items. Relationships are included only when both endpoints are present, preventing detached accessibility links.

When thoughts are omitted, the spatial representation exposes **Open complete searchable thought list**. The list preserves all thoughts and their hierarchy without RealityKit effects. In the packaged 180-thought fixture, the Atlas exposes 18 islands and reports that the other 162 thoughts are available in the complete list.

Renderer reconciliation and accessibility projection use separate signposts and separate report entries, so accessibility-client overhead is not misreported as frame rendering.

## Packaged-app acceptance

The ad-hoc signed `.build/Focus Space.app` was exercised directly:

- selecting a thought framed its branch while retaining the camera angle
- `Command-0` returned from that branch to the canonical Atlas
- `Command-F` found and framed `Focus item 146` within the 180-thought fixture
- the 180-thought spatial accessibility view exposed 18 contextual roots plus the complete-list action
- the complete list identified itself as all 180 thoughts
- `Command-Q` terminated Focus Space independently of Terminal

Automated tests also cover the native magnification monitor, stable magnification origin, two-finger camera-pan origin, two-finger branch-depth lock, selection framing, connected-component translation, renderer preview, and camera reset.

## Final physical-trackpad checklist

Run this once against the packaged app before calling the tactile feel accepted:

1. On **Dense map**, pinch and stretch slowly, then quickly. The camera must track continuously in both directions and must be able to return to the full map.
2. With no thought selected, drag with two fingers left/right and up/down. The universe must follow the fingers without changing thought attention.
3. Select a parent and move two fingers vertically over it. The whole branch must move through depth continuously and commit as one Undo step.
4. In the Atlas, Option-drag an island. Its preview must stay under the pointer, its connected component must preserve relative layout, and Undo must restore the whole move.
5. Select a root, then a descendant. Each selection must frame the corresponding family without a jump or angle change.
6. Press `Command-0`. The canonical Atlas or whole-map view must return.
7. Repeat steps 1–6 on **Large map (180 thoughts)** and note any visible stall, dropped preview, or motion that feels detached.

The automated diagnostic exceeds 30 fps in every matrix cell, but it cannot judge physical resistance, gesture direction, or subjective spring feel. A short small-map and large-map recording should accompany that final hands-on pass. QuickTime screen recording was unavailable in the automated session, so those two recordings are intentionally not represented by still screenshots.
