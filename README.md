# Film Chef

Film Chef is a native macOS photo editor for building, previewing, and exporting film-emulation looks. It is written in SwiftUI and Core Image, with editable JSON recipes that describe film stocks, process behavior, grain, halation, sharpness, color response, and output intent.

The project is early, useful, and intentionally open-ended: the renderer is profile-driven today, with room for calibrated spectral data, measured H-D curves, grain datasets, and LUT-backed profiles later.

## Highlights

- Native SwiftUI macOS app with a three-pane editor: recipes, preview, and inspector controls
- Multi-photo import, `.filmchef` project files, edit history, undo/redo, and named variants
- Non-destructive local adjustment layers with radial, linear, brush, and path masks, including direct preview editing
- Original, edited, split, and side-by-side preview modes with bounded pan, loupe placement, zoom, and draggable comparison
- RGB, luminance, and RGB parade scopes with clipping readouts and pixel sampling
- ImageIO export to JPEG, PNG, or TIFF with quality, scale, metadata, ICC profile, and validated naming templates
- Background batch export for every photo in the current project with progress and cancellation
- Cancelable async preview rendering in-app, plus synchronous rendering for tests
- JSON-backed recipes that are easy to inspect, edit, and share
- In-app recipe editor for metadata, exposure, capture filter, process, grain, halation, sharpness, renderer, and output fields

## Included Recipes

- Ilford HP5 Plus 400
- Kodak Tri-X 400
- Kodak Gold 200
- Kodak Portra 400
- Kodak Portra 800
- CineStill 800T
- Kodak Ektachrome E100
- Fujifilm Velvia 50
- Kodak Vision3 250D

## Requirements

- macOS 14 or newer
- Xcode or Xcode command line tools
- Swift 5.9+

## Quick Start

Build, bundle, and launch the app:

```bash
./script/build_and_run.sh
```

Build without launching:

```bash
swift build
```

Run the core test runner:

```bash
./script/test.sh
```

Use `./script/test.sh` as the canonical test command instead of `swift test`. It runs `FilmChefCoreTests` and writes coverage output under `.build/`.

Verify the staged app bundle:

```bash
./script/build_and_run.sh --verify
```

Package a release-style app archive:

```bash
./script/package_release.sh
```

Optional signing and notarization:

```bash
SIGN_IDENTITY="Developer ID Application: Example" ./script/package_release.sh

NOTARIZE=1 \
  SIGN_IDENTITY="Developer ID Application: Example" \
  NOTARYTOOL_PROFILE="film-chef-notary" \
  ./script/package_release.sh
```

For notarization without a keychain profile, pass `APPLE_ID`, `APPLE_TEAM_ID`, and `APP_SPECIFIC_PASSWORD` with `NOTARIZE=1`.

Generated build output is staged under `dist/` and `.build/`; neither should be committed.

## Project Layout

```text
Sources/FilmChef/App/              App entry point and commands
Sources/FilmChefCore/Models/       Recipe, project, and adjustment models
Sources/FilmChefCore/Stores/       Editor state, projects, and recipe loading
Sources/FilmChefCore/Services/     Core Image processing, calibration parsing, and rendering
Sources/FilmChefCore/Views/        SwiftUI editor views
Sources/FilmChefCore/Resources/    Bundled recipe JSON files
Tests/FilmChefCoreTests/           Executable core test runner
script/build_and_run.sh            Build, bundle, and launch script
script/package_release.sh          Build, sign, verify, and archive a release app
script/test.sh                     Test and coverage script
```

## Recipe Authoring

Recipes live in:

```text
Sources/FilmChefCore/Resources/Recipes/*.json
```

Each file contains one resolved film profile. Use a stable `profile_id` and name the file after that slug.

```json
{
  "schema_version": "1.0",
  "profile_id": "example-film-400",
  "display_name": "Example Film 400",
  "manufacturer": "Example",
  "summary": "A short description of the look.",
  "format": {},
  "stock": {},
  "input": {},
  "exposure": {},
  "capture_conditions": {},
  "layer_model": {},
  "characteristic_curves": {},
  "colour_model": {},
  "process": {},
  "grain": {},
  "halation": {},
  "sharpness": {},
  "renderer": {},
  "output": {},
  "calibration": {}
}
```

Supported `stock.family` values:

- `black_and_white_negative`
- `colour_negative`
- `colour_reversal`
- `motion_picture_negative`
- `specialty`

The renderer currently translates descriptive recipe values into Core Image stages. The schema is designed to grow toward calibrated data such as spectral curves, measured density curves, grain spectra, and 3D LUTs without changing the high-level pipeline.

## Export Naming

Export presets use a filename template with these supported tokens:

- `{photo}`: source photo name without extension
- `{recipe}`: selected recipe display name
- `{format}`: export format label

Templates with unknown or unmatched brace tokens are rejected before export or preset save.

## Calibration Assets

Calibration import accepts `.cube`, `.json`, `.csv`, and `.txt` assets. JSON assets can declare explicit types with `asset_type` or `asset_types`; supported values include `spectral_curves`, `density_curves`, and `grain_spectra`. JSON assets can also provide an `rgb_scale` object with `red`, `green`, and `blue` values.

## Roadmap

Film Chef is an initial implementation. Areas that still need deeper work include:

- Curve and matrix editing for advanced recipe authoring
- Persistent user library metadata and bookmark refresh flows
- Named non-destructive edit stacks with richer comparison workflows
- Richer before/after review controls and saved review workspaces
- Scope overlays and more advanced histogram tooling
- Camera-profile ingestion and deeper RAW/color-management support
- Render cache tuning and detailed export diagnostics
- Export presets and delivery recipes
- App icon assets and update distribution

## Contributing

Contributions are welcome. Keep changes focused, native to the existing SwiftUI app shape, and covered by the project scripts where practical.

Before opening a pull request, run:

```bash
./script/test.sh
swift build
```

For app-flow, resource-bundle, packaging, or recipe changes, also run:

```bash
./script/build_and_run.sh --verify
```

Recipe changes should usually be made in individual JSON files under `Sources/FilmChefCore/Resources/Recipes/`. If the recipe schema changes, update the model, loader, and this README together.

Commit messages should use conventional commits, for example:

```text
feat: add recipe import validation
fix: handle missing recipe JSON
docs: refresh recipe authoring notes
```

## License

Film Chef is released under the [MIT License](LICENSE). Copyright (c) 2026 Forjd.
