# Film Chef

Film Chef is a macOS SwiftUI photo editing app focused on film emulation. It lets a user import a photo, choose a film recipe from the sidebar, preview the edited image, adjust the look, and export the result.

## Current Features

- Native macOS three-pane layout:
  - film recipes in the left sidebar
  - photo preview in the center
  - recipe details and controls on the right
- Photo import via the macOS file picker
- Export to JPEG or PNG
- JSON-backed film recipes for easy editing and sharing
- Two starter recipes:
  - Ilford HP5 Plus 400
  - Kodak Gold 200
- Core Image rendering with exposure, brightness, contrast, saturation, temperature/tint, highlight/shadow, grain, and vignette adjustments

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

## Recipe Config

Recipes live here:

```text
Sources/FilmChef/Resources/Recipes/*.json
```

Each file contains one recipe object. Add a new recipe by creating a JSON file named after its stable `id`, with this shape:

```json
{
  "id": "example-film-400",
  "name": "Example Film 400",
  "maker": "Example",
  "iso": 400,
  "stockType": "color",
  "summary": "A short description of the look.",
  "parameters": {
    "exposure": 0.0,
    "brightness": 0.0,
    "contrast": 1.0,
    "saturation": 1.0,
    "temperature": 0.0,
    "tint": 0.0,
    "highlights": 1.0,
    "shadows": 0.0,
    "grain": 0.1,
    "vignette": 0.1
  }
}
```

Supported `stockType` values:

- `color`
- `blackAndWhite`

Parameter notes:

- `exposure`: exposure value adjustment in EV
- `brightness`: Core Image brightness trim
- `contrast`: `1.0` is neutral, higher increases contrast
- `saturation`: `1.0` is neutral, `0.0` is monochrome
- `temperature`: offset from neutral color temperature for color recipes
- `tint`: green/magenta tint offset for color recipes
- `highlights`: `1.0` is neutral, lower softens highlights
- `shadows`: shadow lift amount
- `grain`: synthetic grain amount
- `vignette`: vignette intensity

## Project Layout

```text
Sources/FilmChef/App/          App entry point and commands
Sources/FilmChef/Models/       Recipe and adjustment models
Sources/FilmChef/Stores/       App state and recipe loading
Sources/FilmChef/Services/     Core Image processing
Sources/FilmChef/Views/        SwiftUI views
Sources/FilmChef/Resources/    Per-recipe JSON resources
script/build_and_run.sh        Build, bundle, and launch script
```

## Codex Run Button

The Codex app action is configured in:

```text
.codex/environments/environment.toml
```

It points to `./script/build_and_run.sh`.

## License

Film Chef is released under the MIT License. Copyright (c) 2026 Forjd.
