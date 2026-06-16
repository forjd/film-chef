# Film Chef Universal iOS App Plan

This plan describes the path from the current macOS SwiftPM app to a polished universal iPhone and iPad app while preserving the existing macOS product. The intent is to reuse the recipe-driven Core Image renderer, project model, and portable SwiftUI components, then build platform-specific app shells around that shared foundation.

The key sequencing rule is simple: decisions that the first iOS proof of concept depends on must happen before the iOS shell. Build topology, minimum OS version, source-photo references, preview memory behavior, export lifecycle, and shared test execution are early architecture work, not late stabilization.

## Target Outcome

Film Chef should become a universal Apple-platform photo editor with:

- Native iPhone and iPad workflows for importing, previewing, adjusting, saving, and sharing edited photos.
- A first-class iPad editing layout that feels close to the current desktop app.
- A compact iPhone workflow optimized around one task at a time: photo, recipe, adjustments, review, export.
- Shared recipe parsing, validation, rendering, project persistence, export naming, calibration logic, and reusable SwiftUI controls across macOS and iOS.
- A project/source-reference model that can explain what is portable across devices and what needs relinking.
- Continued support for the existing macOS app, recipes, packaging path, and project format.

## Current Starting Point

The codebase is already in a favorable shape for a port:

- The rendering engine is recipe-driven and platform-neutral today in `FilmPipelineRenderer`; it imports only `CoreGraphics`, `CoreImage`, and `Foundation`.
- Recipes are JSON resources under the SwiftPM `FilmChefCore` target and can remain a shared package resource bundle if the recipe loader and resources stay in the same resource-owning target, or if the loader gets an explicit public bundle/URL provider.
- Most editor behavior is centralized in `EditorStore`.
- `ProjectStore` is platform-neutral at the import level; its iOS work is about the meaning of photo references and storage, not basic Codable persistence.
- `ImageProcessor` already uses ImageIO for the default export path. Its AppKit dependency is mostly preview image return types and the `NSBitmapImageRep` test/format seam.
- The current SwiftUI views provide reusable interaction patterns for preview comparison, masks, histograms, recipe lists, and controls. Several pieces are close to portable, but `NSImage` preview types and `Color(nsColor:)` semantic colors still need platform-neutral replacements.

The main blockers are platform and packaging coupling:

- `Package.swift` currently declares macOS only and exposes only the `FilmChef` executable product.
- Many shared types, stores, and reusable views are `package` or internal scoped. An external Xcode iOS app target cannot consume them without a public API audit; a same-package SwiftPM target can be useful as a compile harness but does not replace a signed app target for TestFlight or App Store work.
- `FilmChefCore` imports `AppKit` in core services and store code.
- The macOS SwiftUI views currently live inside `FilmChefCore`, so an iOS target depending on `FilmChefCore` would also pull in the desktop editor UI.
- Preview images are stored and rendered as `NSImage`.
- Photo import and save/export destination selection still use `NSOpenPanel` and `NSSavePanel`. Recipe import, calibration import, project open, and relink already flow through SwiftUI `.fileImporter` result handlers.
- Source photos are modeled as URL paths plus security-scoped bookmark data. `PhotosPicker` does not provide a stable file URL for every asset.
- The current source load path eagerly rasterizes full-size source pixels for editor state before preview generation. iOS preview imports need a bounded preview proxy before full-resolution export is attempted.
- The main layout is a desktop `NavigationSplitView` with three simultaneous panes and fixed macOS-oriented column widths.
- Tests are a macOS host executable runner, not XCTest/XCUITest. They import `AppKit`, so shared test coverage is not yet platform-clean and does not validate iOS runtime behavior.

## Guiding Principles

- Preserve the macOS app while adding iOS. Avoid broad rewrites that make the current app unstable.
- Let the compiler enforce platform boundaries. Grepping for `AppKit` is not enough because platform coupling can be transitive.
- Keep rendering behavior profile-driven. Do not add iOS-only film looks in Swift.
- Keep platform-specific UI, file picking, Photos access, save panels, and share sheets outside the shared engine.
- Share components where the interaction is genuinely portable. Do not build separate macOS, iPad, and iPhone versions of histograms, sliders, recipe rows, or preview primitives unless the platform requires it.
- Keep `./script/test.sh` as the command entry point for local verification, but migrate shared assertions toward XCTest so the same behavior can run under macOS and iOS Simulator.
- Treat large image memory, preview downsampling, render cancellation, export progress, color output, and backgrounding as first-slice iOS concerns.
- Make project schema compatibility explicit whenever iOS writes a new kind of photo reference.
- Treat Swift concurrency and sendability as part of the port. `CIImage`, `CGImage`, `CIContext`, render jobs, detached work, and `@MainActor` editor state need explicit isolation rules before iOS workloads scale.

## Build and Module Topology

Before Phase 3, choose the topology that the iOS app will actually consume and the minimum iOS/iPadOS version the first proof of concept is allowed to target. Because the plan uses `PhotosPicker`, `ShareLink`, `Transferable`, and `NavigationSplitView`, the initial floor should be iOS/iPadOS 16 or newer unless those APIs are replaced.

- Option A: add SwiftPM iOS-capable targets as compile harnesses where `package` access remains usable. Use this only to enforce boundaries and run shared tests; it is not the real app packaging path.
- Option B: add an Xcode workspace/project with signed iOS and iPadOS app targets that consume SwiftPM library products, then promote the required core and UI APIs from `package` or internal to `public`.

For a shippable iPhone/iPad app, Option B is the required product topology. Option A remains useful as an early compiler guard.

Either option must satisfy the same constraints:

- `Package.swift` declares the supported iOS/iPadOS platform version.
- A library product exposes the platform-neutral core.
- Target-level separation is mandatory; folder-only boundaries are not enough.
- The shared target compiles for iOS before any real iOS UI work begins.
- The macOS executable depends on shared core plus macOS UI/services and continues to build.
- Recipe resources have one source of truth. The recipe loader and recipes either live in the same resource-owning SwiftPM target, or the loader accepts an explicit public bundle/URL provider.
- If an Xcode app target consumes shared modules, the public API audit includes model/store APIs and any reusable SwiftUI views.
- Any phase that enables iOS project import/export must also include installed-app document type declarations, exported type declarations, and resource-copy verification for that app target.

Recommended target shape:

- Shared domain: models, recipe schema, validation, calibration parsing, export naming, project schema.
- Shared rendering: Core Image loading, preview rendering, histogram sampling, export encoding, color management.
- Shared editor state: selected recipe, adjustments, variants, local masks, history, source references, project state.
- Shared UI components: portable SwiftUI controls, histogram/scope rendering, recipe rows, preview building blocks, inspector controls, shared semantic colors, and platform-neutral preview interaction state that do not import AppKit or UIKit.
- Platform services: photo import, document import/export, save panels, share sheets, Photos library access, app lifecycle, file coordination.
- Platform UI shells: macOS three-pane editor, iPad editor, iPhone editor.

## Phase 1: Compiler-Enforced Boundaries

Goal: separate the existing macOS UI and platform services from shared code, and make the intended iOS boundary compile early.

Work:

- Choose the build topology from the section above. If the first real iOS app will ship through Xcode, create the Xcode app target/workspace path now; keep any SwiftPM iOS target as a compile harness.
- Decide and document the minimum iOS/iPadOS version for the proof of concept before adding platform declarations. Start at iOS/iPadOS 16 unless replacing the APIs listed in the topology section.
- Add the library product, platform declarations, and access-control audit required by that topology.
- Define resource-bundle ownership while splitting targets. Recipes must either remain with `RecipeStore` in the same resource-owning target or move behind an injected public bundle/URL provider.
- Move the current macOS app shell and desktop composition out of the shared core target:
  - `ContentView`
  - `SidebarView`
  - the macOS-specific portions of `ControlsView`
  - the macOS-specific portions of `PreviewPaneView`
- Carve out reusable SwiftUI pieces into a shared UI component layer where they can remain platform-neutral:
  - histogram/scope rendering,
  - inspector sections, info rows, and slider controls,
  - recipe rows and selection controls,
  - preview image building blocks,
  - compare, sampler, zoom, pan, and local-mask interaction state.
- Replace AppKit semantic colors such as `Color(nsColor:)` with a shared semantic color palette that maps to macOS and iOS system colors.
- Define a platform-neutral preview interaction model before freezing shared preview primitives. Platform-specific gesture adapters can then map mouse, touch, pointer, and keyboard behavior onto that model.
- Keep the current `FilmChef` executable working by depending on shared core, shared UI components, macOS services, and the macOS UI shell.
- Add a short architecture note documenting what may import `AppKit`, `UIKit`, or `PhotosUI`.
- Add a mechanical iOS compile guard, such as a thin iOS target or `xcodebuild` check that imports the shared core and shared UI components.
- Keep the existing macOS app-flow verification in place for changes that touch packaging, resources, file types, project persistence, export, or recipes.

Exit criteria:

- A written module boundary exists.
- The minimum iOS/iPadOS version and the real app packaging topology are documented.
- The existing macOS views are no longer part of the shared core target.
- Reusable views and controls that leave the macOS target have the access level required by the chosen topology.
- Recipe resource ownership is documented and verified by the selected target split.
- The team can point to which targets must compile on iOS and which targets are macOS-only.
- The shared core target compiles for iOS without importing AppKit.
- The macOS app still builds and runs with no required user-facing behavior changes.

## Phase 2: Platform-Neutral Core, Previews, Sources, and Tests

Goal: remove AppKit from the shared engine/editor state and make the first iOS import-render-export slice possible without relying on macOS URL semantics.

Work:

- Replace `NSImage` in shared preview paths with a platform-neutral preview value:
  - Use a small `RenderedPreview` or equivalent type, not bare `CGImage?`.
  - Store the `CGImage`, pixel dimensions, display scale, normalized orientation, color space, CI/render pixel format, rendering intent, and byte cost for cache accounting.
  - Keep `CIImage` for internal render graphs.
  - Render through SwiftUI using cross-platform image initializers in shared UI components.
- Update `EditorStore` preview state, original/edited/displayed preview accessors, and preview render cache to use the portable preview value.
- Rework the preview rasterize-and-sample path together, because histogram generation currently shares the same rendered bitmap as preview creation.
- Make preview color behavior explicit in this phase, not during late polish. Preview rendering and final export should declare their color spaces and provide early sRGB and Display P3 parity checks.
- Narrow the `ImageProcessor` cleanup to the AppKit remnants:
  - Replace `NSImage`-returning methods with preview/`CGImage` returning methods.
  - Replace the internal use of `NSBitmapImageRep.FileType` with a private platform-neutral export format enum.
  - Rework the injectable `NSBitmapImageRep` test seam around encoded data, `CGImage`, or the private export format enum.
- Add preview-sized source loading before full rasterization:
  - Prefer file representations from importers where possible.
  - Use ImageIO/Core Image downsampling for preview loads before creating full-size working pixels.
  - Avoid eager full-resolution decode during import and validation; use `CGImageSource` metadata/properties and bounded thumbnails for the editor preview path.
  - Normalize EXIF orientation consistently for preview, sampling, masks, and export, and keep enough orientation metadata to explain how the source was interpreted.
  - Preserve full-resolution source access for final export.
- Add real cancellation for stale preview renders during rapid recipe and slider changes:
  - Use structured render jobs or a render actor instead of unstructured detached work.
  - Check cancellation before and after expensive Core Image stages and before histogram sampling.
  - Treat cancellation as stopping obsolete work, not only ignoring stale results.
- Audit Swift concurrency and sendability for shared rendering/editor code:
  - isolate `CIContext` ownership,
  - decide how `CIImage` and `CGImage` cross task boundaries,
  - keep `EditorStore` mutation on the main actor,
  - remove or wrap detached work patterns that cannot be reasoned about under strict concurrency.
- Define a `PhotoSource` or source-reference abstraction before building the iOS app shell:
  - macOS URL plus security-scoped bookmark.
  - app-container copied file for iOS proof of concept, clearly marked as app-local unless packaged into a portable document.
  - optional Photos asset identifier for a later linked-asset mode.
  - display name, stable item identity, content type, original filename/extension, metadata source, storage location, source orientation, and relink needs.
- For the iOS proof of concept, default to copying imported source pixels into app storage. This is the most uniform path for `PhotosPicker`, document picker imports, offline use, and predictable relaunch behavior. Copy the original file representation when available; if only data is available, define the filename, content type, metadata, and RAW/orientation fallback behavior.
- Do not let platform services hand raw temporary picker URLs to shared editor state as durable project references. The import service should consume security scope, copy or bookmark as needed, then return a durable `PhotoSource`.
- Decide the initial schema-versioning and forward-compatibility policy:
  - when to bump `FilmProject.schemaVersion`,
  - what an older macOS build should do with an unsupported iOS source-reference kind,
  - how the loader preflights `schemaVersion` or a future package manifest before decoding the full project,
  - whether portable projects require source pixels inside a `.filmchef` package/document,
  - whether app-container storage keyed by project ID is allowed only for an explicitly non-portable app-local project library.
- Move the remaining `NSOpenPanel` and `NSSavePanel` usage out of shared `EditorStore`, focusing on:
  - photo import,
  - project save,
  - recipe export,
  - single-photo export,
  - batch export destination selection.
- Add platform service protocols for:
  - photo import,
  - recipe import,
  - calibration import,
  - project open/save,
  - single-photo export/share,
  - batch export destination selection.
- Build the photo-import protocol around durable `PhotoSource` results. The existing `presentsPhotoImportPanel` seam can inform macOS UI behavior, but it should not define the cross-platform import contract.
- Keep existing macOS behavior by implementing those protocols with the current panel and `.fileImporter` flows.
- Begin migrating the shared test suite from the custom executable runner to XCTest:
  - Keep `./script/test.sh` as the command users run.
  - Add a SwiftPM `.testTarget` or Xcode XCTest target for platform-clean shared logic.
  - Update `./script/test.sh` internals and coverage export paths so the new XCTest coverage actually runs under the canonical command.
  - Move platform-clean shared assertions into an XCTest target that can run on macOS and iOS Simulator.
  - Rework AppKit-dependent test seams as preview output moves from `NSImage` to the portable preview value.

Exit criteria:

- Shared model/rendering/editor files no longer import `AppKit`.
- Shared core and shared UI components compile for iOS.
- Preview import can load a bounded preview without full-resolution rasterization.
- Rapid render changes cancel obsolete work rather than only discarding obsolete results.
- The selected `PhotoSource` and project schema policy are documented.
- Unsupported future project/source-reference schemas fail through an intentional preflight error.
- `./script/test.sh` and `swift build` pass for macOS.
- A platform-clean shared XCTest subset can run in an iOS Simulator target.

## Phase 3: Minimal iOS App Shell

Goal: create a minimal iOS target that launches, loads bundled recipes, imports one photo through the chosen source model, renders a preview, and exports or shares the result.

Work:

- Add the iOS app target through the chosen topology. If using Xcode, the iOS path needs normal signing, asset catalogs, launch screen configuration, entitlements, Simulator destinations, archive support, and TestFlight upload.
- Keep `swift build` for package-level macOS verification, but use `xcodebuild` for iOS build and test workflows.
- Create an iOS app entry point with its own `@main` app type.
- Add iOS Info.plist document/exported type declarations for every file flow shipped in this phase. If project import/export is included before Phase 4, `.filmchef` ownership and conformance must be declared and verified in the installed app.
- Add iOS implementations for platform services:
  - `PhotosPicker` for library import, requesting file representations first and immediately copying original source bytes into the chosen app/project storage.
  - `fileImporter` for recipe, calibration, and document-based photo imports. Project import can wait until the Phase 4 storage and document-type decisions are complete.
  - `fileExporter`, `FileDocument`, `Transferable`, or a document picker for recipe export and any project file flow deliberately pulled into this phase.
  - `ShareLink` or `UIActivityViewController` for edited image sharing from a temporary export file, not from an unbounded in-memory encoded `Data` blob.
  - a separate save-to-Photos path if saving back to the Photos library is part of the first release.
- Verify bundled recipes load from the chosen resource source in the installed Simulator app. Treat this as a primary proof-of-concept risk for a mixed Xcode/SwiftPM app, not a final checkbox.
- Render a preview from an imported image using the shared renderer, normalized orientation, explicit preview color settings, and downsampled preview path.
- Add an async file-backed export/share service for single-photo output:
  - progress and cancellation,
  - temp-file cleanup,
  - iOS background-task handling for long writes,
  - metadata preservation from the stored source when available,
  - no main-actor full-image render or large encoded `Data` requirement for normal export.
- Keep the first iOS target intentionally narrow: one photo, one selected recipe, basic adjustments, basic export/share.

Exit criteria:

- iOS app launches in Simulator.
- Bundled recipes appear from the shared resource source.
- A photo can be imported through `PhotosPicker` or document import, copied or referenced through the chosen `PhotoSource`, loaded as a bounded preview, and rendered with correct orientation.
- Rapid adjustment changes cancel stale preview renders at the render-job level.
- The rendered result can be exported to a temp file and shared or saved through the iOS export path with progress, cancellation, and cleanup.
- Preview and export produce acceptable parity for sRGB and Display P3 smoke fixtures.
- A thin iOS unit or smoke test imports shared core successfully.
- macOS verification still passes.

## Phase 4: Projects, Recipes, and Files on iOS

Goal: make cross-device work reliable and understandable before investing heavily in full iPad and iPhone editor surfaces.

Work:

- Implement the project storage model chosen in Phase 2:
  - document-based `.filmchef` files,
  - app-local project library,
  - app-container source storage keyed by project ID,
  - iCloud Drive-compatible documents,
  - or a hybrid model.
- Treat document-based projects as an explicit architecture decision. The macOS app currently uses `WindowGroup` plus open-file routing, not a `DocumentGroup` architecture.
- For portable projects, require copied source pixels to live inside a package/bundle project format or another document-scoped storage model. App-container sidecar storage may be used for an app-local library, but those projects must be labelled non-portable and must not export as self-contained `.filmchef` files unless their assets are packaged.
- Bump and document project schema version if new source-reference kinds are written.
- Preflight project schema/version metadata before decoding the full project body so unsupported future schemas produce intentional errors.
- Preserve compatibility with the current `.filmchef` schema where possible.
- Redesign photo references for iOS instead of assuming the macOS URL model transfers directly:
  - macOS can continue to use security-scoped bookmarks and absolute-path fallback.
  - iOS document-picker URLs may use security-scoped bookmarks, but they are not portable across every import path.
  - Photos imports should use copied source files for the first implementation unless asset-linking is deliberately added.
  - `PHAsset.localIdentifier` can be added later for linked Photos-library workflows, with clear permission and missing-asset behavior.
  - The current absolute-path fallback should be treated as macOS-only.
- Add relink/recover flows for missing project photos.
- Support importing and exporting editable recipe JSON.
- Support calibration asset import with the existing `asset_type` and `asset_types` behavior.
- Ensure export naming templates behave consistently across platforms.
- Finalize `.filmchef` file type declarations, exported image type declarations, and document access behavior here unless project file flows were deliberately pulled into Phase 3.
- If `.filmchef` changes from a single JSON file to a package/bundle, update UTType conformance and installed-app verification instead of leaving the type as `public.json`.
- Model iOS export as producing files/data that can be handed to system document and share APIs, not as direct writes to an arbitrary save-panel URL.

Exit criteria:

- Projects can be opened, saved, closed, and reopened on iOS.
- Recipe import/export is compatible with macOS.
- Missing photo references have a clear recovery path.
- File and Photos permissions failure states are handled cleanly.
- An older unsupported project/source-reference version fails through schema preflight with an intentional error instead of a raw decoding error, relink prompt, or partial undefined behavior.

## Phase 5: iPad Editing Experience

Goal: ship an iPad layout that preserves the power of the macOS editor while respecting touch, pointer, keyboard, and size-class behavior.

Work:

- Build an adaptive iPad `NavigationSplitView`:
  - recipe/project browser in the sidebar,
  - preview in the center,
  - controls in the inspector column where space allows.
- Define split-view collapse behavior for portrait, Slide Over, Split View, Stage Manager, and compact widths.
- Reuse shared UI components for histograms, recipe rows, sliders, local-adjustment controls, and preview primitives.
- Keep preview interaction parity where it fits:
  - original/edited/split comparison,
  - pinch zoom and pan,
  - sampler,
  - histogram and clipping feedback,
  - local mask editing.
- Implement the gesture arbitration model defined during the shared preview extraction:
  - sampler versus pan,
  - mask editing versus pan/zoom,
  - split divider drag versus image gestures,
  - pointer and trackpad behavior.
- Tune controls for touch:
  - larger hit targets,
  - sliders with explicit values,
  - grouped inspectors,
  - sheet or popover editing for dense recipe settings.
- Add keyboard shortcut support where useful for iPad keyboards.

Exit criteria:

- iPad supports the core editing loop without falling back to cramped sheets.
- Touch, pointer, and keyboard interactions are predictable.
- Existing macOS interaction patterns are preserved where they fit.
- Shared components are reused where they remain platform-appropriate.

## Phase 6: iPhone Editing Experience

Goal: build a compact workflow rather than compressing the desktop layout.

Work:

- Create a tab or step-based iPhone structure:
  - Photo,
  - Recipe,
  - Adjust,
  - Review,
  - Export.
- Keep the preview as the primary surface and reveal controls through bottom sheets or dedicated screens.
- Prioritize the most common controls in the first release:
  - intensity,
  - exposure,
  - contrast,
  - saturation,
  - grain toggle,
  - recipe selection,
  - compare mode.
- Move advanced recipe editing, calibration details, batch export, and detailed histogram tools behind secondary screens.
- Rework local mask editing for touch:
  - clear edit mode,
  - visible handles,
  - undo-friendly gestures,
  - no conflict with pan and zoom.
- Add compact export/share flow with clear file format and quality choices.
- Validate that shared controls still fit iPhone ergonomics; fork only the components that need a genuinely different interaction model.

Exit criteria:

- iPhone users can complete the primary photo editing loop quickly.
- Advanced tools remain available without dominating the main interface.
- Preview gestures do not conflict with mask editing or sampler interactions.
- Export/share choices are clear and recover cleanly from permission or storage failures.

## Phase 7: Performance, Memory, Color, and Backgrounding

Goal: make large-photo editing stable and visually trustworthy on iPhone and iPad.

Work:

- Profile preview rendering on representative devices and Simulators.
- Tune iOS preview dimensions while keeping final export full quality. The current 4096px preview ceiling is a useful reference point; at half-float RGBA it can create roughly 134 MB square preview buffers before Core Image intermediates.
- Verify the downsampled preview path added earlier under large Photos imports.
- Avoid retaining multiple full-size rendered images unnecessarily.
- Preserve the existing `CIContext` reuse pattern and verify it on device under rapid preview and export workloads.
- Validate RAW import behavior and decide whether RAW editing is in scope for the first iOS release.
- Validate preview and output color on device, including sRGB, Display P3, embedded profiles, rendering intent, and metadata preservation where supported.
- Add progress states for slow preview renders and exports.
- Add lifecycle handling for memory pressure, backgrounding, app suspension, and scene phase changes:
  - cancel or pause active preview renders,
  - purge preview/render caches and Core Image caches where appropriate,
  - checkpoint app-local project state before suspension,
  - clean stale temp export files.
- Audit single-photo and batch export for backgrounding, cancellation, app suspension, and thermal constraints. Pay special attention to existing detached work patterns before enabling batch export on iOS.

Exit criteria:

- Large images do not routinely terminate the app.
- Rapid slider changes cancel stale renders.
- Export progress and cancellation work on device.
- Memory-pressure handling can evict preview caches without corrupting editor state.
- App suspension does not lose app-local project state or leave stale export temp files behind.
- Preview quality and responsiveness are acceptable on the minimum supported devices.
- Color output matches the intended profile behavior closely enough for a photo-editing product.

## Phase 8: Test Coverage and Verification

Goal: keep shared behavior stable while adding platform-specific app flows.

Work:

- Keep `./script/test.sh` as the canonical local command, but have it run the modernized shared tests rather than permanently depending on the custom executable runner.
- Update `./script/test.sh` internals and coverage reporting for XCTest. The command name stays stable, but the current build-run-`llvm-profdata` executable-runner flow should not remain the permanent coverage path.
- Move or duplicate the shared logic coverage into XCTest targets for:
  - recipe loading and validation,
  - preview rendering smoke tests,
  - cross-platform render parity for the same source, recipe, adjustments, color settings, and declared tolerance on macOS and iOS Simulator,
  - EXIF orientation normalization for preview, masks, sampling, and export,
  - export encoding and naming templates,
  - project persistence and schema compatibility,
  - unsupported future schema/source-reference preflight errors,
  - calibration asset parsing,
  - local adjustment serialization and rendering behavior,
  - source-reference encoding and relink behavior.
- Keep any remaining custom-runner coverage only as a temporary migration aid.
- Add an iOS XCTest target that runs the platform-clean shared subset in Simulator.
- Add iOS XCUITest or app-level smoke coverage for:
  - app launch,
  - recipe list loading,
  - photo import,
  - adjustment changes,
  - export/share flow,
  - project open/save.
- Add an iOS simulator verification script around `xcodebuild test -destination`, rather than trying to adapt the macOS bundle-building script directly.
- Keep macOS app-flow verification for shared changes that touch resources, project persistence, export, recipes, file types, or packaging.
- For package, resource-bundle, file-type, signing, or release-layout changes, run `./script/build_and_run.sh --verify` and add a release-packaging dry run or `script/package_release.sh` check where practical.

Exit criteria:

- Shared tests pass on every core change.
- `./script/test.sh` runs the XCTest-based shared coverage and publishes the expected coverage artifact.
- The shared test subset runs under iOS Simulator.
- macOS verification remains green.
- iOS XCTest/XCUITest runs in Simulator.
- iOS Simulator smoke tests cover the primary editing flow.
- The macOS release packaging path remains independently verifiable.

## Phase 9: Polish and App Store Readiness

Goal: finish the universal app as a product, not just a port.

Work:

- Add app icons, launch screen, accent color, and platform-specific assets.
- Add Photos privacy strings and document access descriptions.
- Review permission copy for Photos import, save-to-Photos, document access, and missing source recovery.
- Add onboarding only where it removes real permission or import confusion.
- Improve empty states for no photo, no recipe, missing project photo, and failed export.
- Validate Dynamic Type, VoiceOver labels, contrast, reduced motion, and touch target sizes.
- Add localized strings infrastructure before broader copy hardening.
- Prepare App Store metadata, screenshots, privacy nutrition labels, and support URL.
- Reconfirm whether the Phase 1 minimum iOS/iPadOS version should be raised based on performance, device coverage, or APIs adopted after the proof of concept.

Exit criteria:

- The app passes archive, signing, and TestFlight upload.
- Privacy and file access behavior is explainable and reviewed.
- iPhone and iPad screenshots show real product workflows.
- The macOS app remains independently shippable.

## Suggested Milestones

1. Boundary milestone: the real app topology, minimum OS version, resource ownership, shared core, and shared UI components compile for iOS, while the macOS app still runs.
2. Portable preview/source milestone: AppKit-free preview rendering, explicit color/orientation metadata, downsampled preview loading, real render cancellation, and a documented `PhotoSource` model.
3. Shared test milestone: platform-clean XCTest coverage and render-parity fixtures run on macOS and iOS Simulator.
4. iOS proof-of-concept milestone: import one photo, apply one recipe, cancel stale renders, export/share a file-backed result, and verify bundled recipes in the installed Simulator app.
5. Project compatibility milestone: iOS can open/save projects with intentional source-reference, portability, and schema behavior.
6. iPad MVP milestone: three-area adaptive editor with core controls and explicit gesture arbitration.
7. iPhone MVP milestone: compact one-photo editing workflow.
8. Performance milestone: stable large-photo rendering, export, color output, and backgrounding behavior on target devices.
9. TestFlight milestone: signed universal app with polished permissions and core flows.

## Open Product Decisions

- Should the first iOS release support batch export, or should batch export remain macOS/iPad-only until performance is proven?
- After the copy-in proof of concept, should projects also support linked Photos assets, linked document-picker files, or both?
- Should portable copied source pixels live inside a future `.filmchef` package/bundle, and should app-container storage be limited to a non-portable app-local library or combined in a hybrid model?
- Should advanced recipe editing ship on iPhone, or be limited to iPad/macOS initially?
- Should the Phase 1 minimum iOS/iPadOS version be raised for performance or API reasons?
- Is RAW import required for the first release?
- Should iCloud Drive project sync be part of the initial universal app or a later release?

## Recommended First Implementation Slice

Start with the smallest slice that validates the architecture:

1. Choose the real app topology, minimum iOS/iPadOS version, and target-level separation. Use SwiftPM iOS targets only as compile/test harnesses unless the Xcode app path is also in place.
2. Add the shared library product, public API surface, and recipe resource-bundle strategy needed for the app shell to consume core code.
3. Extract macOS-only UI/services from `FilmChefCore`, while moving portable SwiftUI pieces, semantic colors, and preview interaction state into a shared UI component layer.
4. Convert preview output from `NSImage` to a platform-neutral preview value carrying `CGImage`, pixel size, display scale, orientation, color space, CI/render format, rendering intent, and cache cost.
5. Define the first `PhotoSource` model, copy original file representations for iOS POC imports, and load bounded preview proxies without full-resolution rasterization.
6. Add structured render cancellation and a Swift concurrency/sendability audit for editor and renderer work.
7. Move macOS photo import and save/export panels behind platform service methods that return durable source/export results, not raw temporary picker URLs.
8. Add async file-backed single-photo export/share with progress, cancellation, cleanup, and background-task handling.
9. Migrate a platform-clean shared test subset to XCTest, add render-parity fixtures, and run it in an iOS Simulator target.
10. Add a minimal iOS target with `PhotosPicker` import, installed-app bundled recipe verification, one-photo rendering, and temp-file/transferable sharing.

That slice proves the renderer, resources, editor state, source-reference model, preview memory behavior, tests, and export path can survive the platform split before investing in the full iPhone and iPad interaction model.
