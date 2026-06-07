# Film Chef

Film Chef is a macOS SwiftUI photo editing app focused on film emulation. It lets a user import a photo, choose a film recipe from the sidebar, preview the edited image, adjust the look, and export the result.

## Current Features

- Native macOS three-pane layout:
  - film recipes in the left sidebar
  - photo preview in the center
  - recipe details and controls on the right
- Photo import via the macOS file picker
- Export to JPEG or PNG
- JSON-backed resolved film profiles for easy editing and sharing
- Four starter profiles:
  - Ilford HP5 Plus 400
  - Kodak Gold 200
  - CineStill 800T
  - Kodak Ektachrome E100
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
