# Focus Space

Focus Space is a native macOS spatial workspace where depth represents attention.

## Run

Open `Package.swift` in Xcode and run the `FocusSpace` scheme, or use:

```sh
./Scripts/run-app.sh
```

This builds and opens a proper macOS application bundle. The command returns to
the shell immediately, and quitting Focus Space does not quit or interrupt
Terminal.

To create a launchable, ad-hoc signed app bundle:

```sh
./Scripts/package-app.sh
open ".build/Focus Space.app"
```

Launch a deterministic experience-review scene without touching personal autosave data:

```sh
./Scripts/run-app.sh --demo north-star
```

Available demo slugs are `north-star`, `shallow`, `deep`, `dense`, `parked`, and `empty`.

The first launch creates a small example map. Changes autosave as readable JSON in
`~/Library/Application Support/Focus Space/focus-space.json`.

## Architecture

- `Domain`: renderer-independent focus map and attention semantics
- `Application`: user intents, selection, command history and autosave orchestration
- `Rendering`: a RealityKit adapter that consumes immutable scene snapshots
- `Persistence`: a replaceable JSON repository
- `UI`: the native SwiftUI shell and direct-manipulation interactions

RealityKit types do not cross into the domain or application layers.

## Visual roadmap

- [Visual experience roadmap](plans/visual-experience-roadmap.md)
- [Milestone 1 spatial atmosphere](docs/milestone-1-spatial-atmosphere.md)
- [Milestone 2 node visual language](docs/milestone-2-node-visual-language.md)
- [Milestone 3 spatial relationships](docs/milestone-3-spatial-relationships.md)
- [Milestone 4 camera navigation](docs/milestone-4-camera-navigation.md)
- [Interaction refinements from Ibrahim's review](docs/interaction-refinements.md)
- [Branch focus, shape preferences, and selected notes](docs/branch-focus-shapes-and-notes.md)
- [Visual north star](docs/reference/focus-space-visual-north-star.png)
