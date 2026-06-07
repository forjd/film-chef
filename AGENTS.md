# Agent Notes

This repository contains a SwiftPM macOS SwiftUI app named `FilmChef`.

## Build And Run

Use the project script as the canonical local run path:

```bash
./script/build_and_run.sh
```

Verification:

```bash
./script/build_and_run.sh --verify
swift build
```

The run script stages a local `.app` bundle under `dist/`. Do not commit `dist/` or `.build/`.

## App Shape

- `Package.swift` defines a single executable product, `FilmChef`.
- `Sources/FilmChef/App/FilmChefApp.swift` owns the app entry point and app commands.
- `Sources/FilmChef/Views/ContentView.swift` composes the three-pane layout.
- `Sources/FilmChef/Stores/EditorStore.swift` owns editor state, import/export actions, and preview rendering triggers.
- `Sources/FilmChef/Stores/RecipeStore.swift` loads bundled JSON recipes.
- `Sources/FilmChef/Services/ImageProcessor.swift` owns Core Image loading, preview scaling, and export encoding.
- `Sources/FilmChef/Services/FilmPipelineRenderer.swift` owns the profile-driven Core Image rendering stages.
- `Sources/FilmChef/Resources/Recipes/*.json` contains one editable recipe per file.

## Editing Guidelines

- Keep the desktop layout native: `NavigationSplitView` sidebar, preview, and inspector-style controls.
- Prefer small focused Swift files by responsibility. Avoid merging models, stores, services, and views into one file.
- Recipe changes should normally happen in individual JSON files under `Sources/FilmChef/Resources/Recipes/`, not hardcoded Swift.
- If the JSON schema changes, update `FilmRecipe.swift`, `RecipeStore.swift`, and `README.md` together.
- Keep generated artifacts out of source control. `.gitignore` already excludes `.build/` and `dist/`.
- After Swift edits, run `swift build`. After app flow or resource-bundle edits, run `./script/build_and_run.sh --verify`.

## Commit Style

Use conventional commits for commit messages, such as `feat: add recipe import`, `fix: handle missing recipe JSON`, or `docs: update agent notes`.

## Recipe Schema

Each recipe has:

- `schema_version`: profile schema version
- `profile_id`: stable unique slug
- `display_name`: display name
- `manufacturer`: film maker or profile author
- `summary`: short UI description
- `format`: film format metadata
- `stock`: family, process, box speed, balance, mask, remjet, and anti-halation behavior
- `input`, `exposure`, `capture_conditions`, `layer_model`, `characteristic_curves`
- `colour_model`, `process`, `grain`, `halation`, `sharpness`, `renderer`, `output`, `calibration`

Supported `stock.family` values:

- `black_and_white_negative`
- `colour_negative`
- `colour_reversal`
- `motion_picture_negative`
- `specialty`

Rendering is profile-driven through `FilmPipelineRenderer`. Keep new recipe values descriptive and human-readable; do not introduce binary LUT blobs until calibration data support exists.

## Known Scope

This is an initial implementation. There is no persistent user library, custom recipe import/export UI, before/after split view, histogram, calibrated spectral/LUT data, or non-destructive edit stack yet.
