# Agent Notes

Film Chef is a SwiftPM macOS SwiftUI app for film-emulation photo editing. It uses Core Image for rendering and editable JSON recipes for film profiles.

## Canonical Commands

Run the app through the project script:

```bash
./script/build_and_run.sh
```

Verify changes with:

```bash
./script/test.sh
swift build
```

For app-flow, packaging, or resource-bundle changes, also run:

```bash
./script/build_and_run.sh --verify
```

`./script/test.sh` is the canonical test command; use it instead of `swift test`.

The run script stages a local `.app` bundle under `dist/`. Do not commit `dist/` or `.build/`.

## Project Map

- `Package.swift` defines the `FilmChef` executable and the `FilmChefCoreTests` executable test runner.
- `Sources/FilmChef/App/FilmChefApp.swift` owns the app entry point and app commands.
- `Sources/FilmChefCore/Models/` contains recipe, project, adjustment, and UTType models.
- `Sources/FilmChefCore/Stores/EditorStore.swift` owns editor state, import/export actions, project state, and preview rendering triggers.
- `Sources/FilmChefCore/Stores/ProjectStore.swift` handles `.filmchef` project persistence.
- `Sources/FilmChefCore/Stores/RecipeStore.swift` loads bundled JSON recipes.
- `Sources/FilmChefCore/Services/ImageProcessor.swift` owns Core Image loading, preview scaling, and export encoding.
- `Sources/FilmChefCore/Services/FilmPipelineRenderer.swift` owns the profile-driven Core Image rendering stages.
- `Sources/FilmChefCore/Views/ContentView.swift` composes the native three-pane layout.
- `Sources/FilmChefCore/Views/` contains sidebar, preview, controls, and histogram/scope UI.
- `Sources/FilmChefCore/Resources/Recipes/*.json` contains one editable recipe per file.
- `Tests/FilmChefCoreTests/main.swift` runs focused core tests and coverage through `./script/test.sh`.

## Editing Guidelines

- Keep the desktop layout native: `NavigationSplitView` sidebar, center preview, and inspector-style controls.
- Prefer small Swift files by responsibility. Do not merge models, stores, services, and views into one file.
- Keep rendering behavior profile-driven through `FilmPipelineRenderer`; avoid hardcoding recipe-specific looks in Swift.
- Make recipe changes in individual JSON files under `Sources/FilmChefCore/Resources/Recipes/`.
- If the JSON schema changes, update `FilmRecipe.swift`, `RecipeStore.swift`, and `README.md` together.
- Preserve non-destructive editing behavior for adjustments, snapshots, variants, masks, and project persistence.
- Keep generated artifacts out of source control. `.gitignore` already excludes `.build/` and `dist/`.
- After Swift edits, run `./script/test.sh` and `swift build`.
- After app-flow, packaging, recipe, or resource-bundle edits, also run `./script/build_and_run.sh --verify`.

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

Keep recipe values descriptive and human-readable. Do not introduce binary LUT blobs until calibration data support is ready for them.

## Commit Style

Use conventional commits, for example:

```text
feat: add recipe import validation
fix: handle missing recipe JSON
docs: update agent notes
```
