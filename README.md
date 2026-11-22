# Secret Text Studio – iOS (SwiftUI)

Native iOS proof-of-concept for converting Vietnamese text to cinematic scrambled-character motion videos. Developed in SwiftUI + UIKit drawing + AVFoundation.

## Quick start

1. Install Xcode 16 or later on macOS.
2. Open `SecretTextStudio.xcodeproj`.
3. Select an iPhone Simulator and run the `SecretTextStudio` scheme.

## Implemented in this MVP

- Unicode-grapheme-preserving seeded scramble generator with exact source-index mapping.
- Preview of 12 stylistic motion variations (simplified 2D renderers; not full Metal/3D).
- Create, delete, duplicate, select, and reorder scenes.
- Sentence-based scene split and style presets.
- Audio import from Files, trim start, timeline offset, volume, fade in/out.
- Local frame-by-frame H.264 MP4 export, with optional audio composition.
- JSON autosave for the current project.

## Limitations

This is an MVP, **not** an App Store-ready or professionally validated video editor. No real waveform editing, automated beat extraction, scene transitions, 3D renderer, reliable background export, or long-form stress validation yet. 4K and 60 FPS are device-dependent. Core rendering may be resource-intensive on older devices. Review iOS permission/code-signing requirements before distributing.

## GitHub Actions

`.github/workflows/ios-build.yml` compiles and runs the Unicode scramble smoke test, builds an unsigned iOS Simulator app with Xcode on macOS, and uploads a zipped `.app` artifact if compilation succeeds. Simulator artifacts **cannot** be installed directly on a physical iPhone. Device IPA/TestFlight delivery requires Apple Developer signing.

The workflow starts on pushes to `main`, pull requests, or manual `workflow_dispatch`. Inspect **Actions → iOS Build** for build status, error logs, and available artifacts.

## Source directories

- `App/` SwiftUI entry point
- `Models/` project, scene, audio and motion style models
- `Engines/` scramble, renderer, persistence and exporter
- `Views/` scene, audio, preview and export UI
- `Tests/` algorithm smoke test

Copyright: source is provided as a starting point for your own iOS app.
