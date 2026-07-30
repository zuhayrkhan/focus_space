# Usability milestone U5 — measured scale and interaction feel

Status: completed and accepted on 30 July 2026.

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

Final regression matrix captured on 30 July 2026 from commit `68d3f47`:

| Fixture | Size | Interactive | Presentation | Live preview | Search | Arrange | Spatial accessibility |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 32 | compact | 921 ms | 59.7 fps | 58.6 fps | 0.15 ms | 0.47 ms | 32 |
| 32 | standard | 893 ms | 59.3 fps | 58.2 fps | 0.28 ms | 0.89 ms | 32 |
| 32 | large | 855 ms | 59.3 fps | 55.6 fps | 0.35 ms | 0.96 ms | 32 |
| 65 | compact | 790 ms | 60.0 fps | 52.7 fps | 0.39 ms | 8.31 ms | 5 of 65 |
| 65 | standard | 797 ms | 59.7 fps | 58.9 fps | 0.35 ms | 6.70 ms | 5 of 65 |
| 65 | large | 792 ms | 59.3 fps | 61.4 fps | 0.35 ms | 7.13 ms | 5 of 65 |
| 180 | compact | 960 ms | 57.8 fps | 56.1 fps | 0.60 ms | 20.98 ms | 18 of 180 |
| 180 | standard | 1,020 ms | 58.4 fps | 51.0 fps | 0.32 ms | 15.29 ms | 18 of 180 |
| 180 | large | 1,009 ms | 58.7 fps | 57.8 fps | 0.59 ms | 19.44 ms | 18 of 180 |

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

## Physical-trackpad acceptance

The owner exercised the packaged application on physical trackpads throughout the interaction review and accepted the final behaviour on 30 July 2026. The closing regression used **Large map (180 thoughts)** and selected **Focus item 7**:

- two-finger movement retained the selected branch, selection, inspector context, and camera angle
- pinch and stretch retained that same branch even after zooming beyond the former Atlas distance threshold
- zooming could still return to the complete visible branch without becoming a deselection gesture
- two-finger branch-depth movement remained continuous and committed as one undoable change
- Option-drag retained continuous connected-component preview and one-step Undo
- selecting successive ancestors and descendants framed their families without changing attention
- `Command-0` restored the canonical whole-map context

The repeatable checklist remains:

1. On **Dense map**, pinch and stretch slowly, then quickly. The camera must track continuously in both directions and must be able to return to the full map.
2. With no thought selected, drag with two fingers left/right and up/down. The universe must follow the fingers without changing thought attention.
3. Select a parent and move two fingers vertically over it. The whole branch must move through depth continuously and commit as one Undo step.
4. In the Atlas, Option-drag an island. Its preview must stay under the pointer, its connected component must preserve relative layout, and Undo must restore the whole move.
5. Select a root, then a descendant. Each selection must frame the corresponding family without a jump or angle change.
6. Press `Command-0`. The canonical Atlas or whole-map view must return.
7. Repeat steps 1–6 on **Large map (180 thoughts)** and note any visible stall, dropped preview, or motion that feels detached.

The automated diagnostic exceeds 30 fps in every matrix cell, while the owner's physical pass supplies the resistance, direction, continuity, and spring-feel judgement that automation cannot. No screen recording was retained; acceptance came from the live owner review rather than an automated substitute.

The final release gate then passed all 91 tests, rebuilt the packaged application, validated its property list, and verified its ad-hoc signature.
