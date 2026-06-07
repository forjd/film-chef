# Film Chef

Film Chef is a macOS SwiftUI photo editing app focused on film emulation. It lets a user import a photo, choose a film recipe from the sidebar, preview the edited image, adjust the look, and export the result.

## Current Features

- Native macOS three-pane layout:
  - film recipes in the left sidebar
  - photo preview in the center
  - recipe details and controls on the right
- Multi-photo import via the macOS file picker
- ImageIO-backed export to JPEG, PNG, or TIFF with format, JPEG quality, scale, metadata, ICC output profile, and naming-template settings
- JSON-backed resolved film profiles for easy editing and sharing
- Recipe import and export from the app
- Saveable `.filmchef` project files with multiple photo references, edit history, export settings, and color-management settings
- Edit snapshots with undo, redo, and captured variants
- Non-destructive local adjustment layers with radial, linear, brush, and path masks
- Edited, original, split, and side-by-side preview comparison modes with zoom and draggable split-position controls
- RGB, luminance, and RGB parade scopes with clipping readouts and pointer-driven pixel sampling
- Batch export for every photo in the current project
- Cancelable async preview rendering in the app, with synchronous rendering available to the core test runner
- RAW-development controls, color-management settings, and calibration asset tracking with lightweight LUT, spectral, density, and grain render calibration
- Nine starter profiles:
  - Ilford HP5 Plus 400
  - Kodak Tri-X 400
  - Kodak Gold 200
  - Kodak Portra 400
  - Kodak Portra 800
  - CineStill 800T
  - Kodak Ektachrome E100
  - Fujifilm Velvia 50
  - Kodak Vision3 250D
- Modular Core Image rendering pipeline with profile-driven exposure placement, capture filters, layer response, characteristic curves, process adjustments, halation, grain, MTF/sharpness, and scan/print rendering

## Requirements

- macOS 14 or newer
- Xcode command line tools or Xcode with Swift 5.9+

## Run

Use the project-local run script:

```bash
./script/build_and_run.sh
```

The script builds the SwiftPM target, stages a local app bundle in `dist/`, and launches it as a macOS app.

Useful variants:

```bash
./script/build_and_run.sh --verify
./script/build_and_run.sh --logs
./script/build_and_run.sh --debug
```

Package a release-style app archive:

```bash
./script/package_release.sh
SIGN_IDENTITY="Developer ID Application: Example" ./script/package_release.sh
NOTARIZE=1 \
  SIGN_IDENTITY="Developer ID Application: Example" \
  NOTARYTOOL_PROFILE="film-chef-notary" \
  ./script/package_release.sh
```

For notarization without a keychain profile, pass `APPLE_ID`, `APPLE_TEAM_ID`, and `APP_SPECIFIC_PASSWORD` with `NOTARIZE=1`.

You can also build without launching:

```bash
swift build
```

## Test

Run the package-local test runner:

```bash
./script/test.sh
```

The script runs `FilmChefCoreTests` and writes a coverage JSON report under `.build/arm64-apple-macosx/debug/codecov/`.
Use this script as the canonical test command instead of `swift test`.

## Recipe Config

Recipes live here:

```text
Sources/FilmChefCore/Resources/Recipes/*.json
```

Each file contains one resolved film profile. Add a new profile by creating a JSON file named after its stable `profile_id`, with this top-level shape:

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

Profile module notes:

- `format`: film format metadata such as 35mm frame size
- `stock`: family, process, box speed, native balance, orange mask, remjet, and anti-halation behavior
- `input`: preferred source and working-space intent for the pipeline
- `exposure`: box speed, exposed-at ISO, compensation, middle grey, highlight protection, and pre-film shadow lift
- `capture_conditions`: illuminant, color temperature, lens contrast/flare, and optical filters
- `layer_model`: maps scene RGB into monochrome or red/green/blue emulsion layers
- `characteristic_curves`: human-readable toe, gamma, shoulder, d-min, and d-max channel response
- `colour_model`: palette, warmth, saturation, hue bias, optional toning, and orange-mask density
- `process`: C-41, E-6, B&W, push/pull, contrast, speed, grain, and color shift adjustments
- `grain`: silver grain, dye cloud, slide grain, clumpiness, softness, chromaticity, and tonal distribution
- `halation`: backing/remjet behavior, threshold, strength, radius, and color
- `sharpness`: film MTF blur, scanner blur, acutance, and digital sharpening
- `renderer`: lab scan, projection, or print-style black/white points, contrast, saturation, and MTF
- `output`: output color-space intent, bit depth, and dithering flag
- `calibration`: confidence, source, and notes for the profile

The renderer currently translates these descriptive values into Core Image stages. The schema is designed to allow later calibrated data such as spectral curves, measured H-D curves, grain spectra, or 3D LUTs without changing the app's high-level pipeline.

## Product Gap Tracker

The current implementation has first-pass support for the original ten missing areas, but several remain intentionally shallow:

- Persistent library/projects: `.filmchef` project save/load exists with multiple project items, selectable photo browsing, settings, edit history, and security-scoped bookmark data; bookmark refresh UX and richer library metadata are still needed.
- Non-destructive edit stack: edit snapshots, undo/redo, variants, project persistence, and local masked adjustment layers exist; richer named stacks and freehand mask editing are still needed.
- Recipe import/export UI: app commands and controls exist; schema validation UX and recipe editing are still needed.
- Before/after comparison: original, edited, split, and side-by-side preview modes exist with zoom, split position, a draggable divider, and a first-pass sampler overlay; pan and richer loupe controls are still needed.
- Histogram/scopes: RGB/luminance histogram, RGB parade, channel switching, clipping readouts, and pointer-driven pixel sampling exist; richer scope overlays are still needed.
- Calibrated film data: status models, recipe calibration metadata, calibration asset import/tracking, and lightweight `.cube`, spectral-bias, measured-density, and grain-spectrum render calibration exist; true measured spectral transforms and profile-specific calibration datasets are still needed.
- RAW/color management: RAW-style exposure, temperature, tint, highlight recovery, persisted color-management intents, and ICC-tagged sRGB/Display P3/linear/extended export writing exist; camera-profile ingestion is still needed.
- Async responsiveness: app preview rendering is cancelable and debounced; progress reporting, render caching, and export backgrounding are still needed.
- Expanded export workflow: ImageIO-backed JPEG/PNG/TIFF export, quality, scale, metadata writing, ICC output profile tagging, naming templates, and project batch export exist; export presets and richer delivery recipes are still needed.
- Production packaging: `script/package_release.sh` creates and verifies a release `.app` archive with optional Developer ID signing, notarization, and stapling; app icon assets and update distribution remain.

## Project Layout

```text
Sources/FilmChef/App/              App entry point and commands
Sources/FilmChefCore/Models/       Recipe and adjustment models
Sources/FilmChefCore/Stores/       App state and recipe loading
Sources/FilmChefCore/Services/     Core Image processing
Sources/FilmChefCore/Views/        SwiftUI views
Sources/FilmChefCore/Resources/    Per-recipe JSON resources
Tests/FilmChefCoreTests/           Executable test runner
script/build_and_run.sh            Build, bundle, and launch script
script/package_release.sh          Build, sign, verify, and archive a release app
script/test.sh                     Test and coverage script
```

## Codex Run Button

The Codex app action is configured in:

```text
.codex/environments/environment.toml
```

It points to `./script/build_and_run.sh`.

## License

Film Chef is released under the MIT License. Copyright (c) 2026 Forjd.
