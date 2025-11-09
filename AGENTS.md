# Repository Guidelines

## Project Structure & Module Organization
- `lib/` holds the Flutter app: `core/` for shared utilities, `data/` for repositories/models, `presentation/` for UI flows, and entrypoints in `main.dart` and `app.dart`.
- Keep feature assets (images, JSON fixtures) under `assets/` when added, and register them in `pubspec.yaml`.
- Tests live in `test/`, mirroring the `lib/` tree; onboarding documents stay in `docs/`; platform shells sit in `ios/`, `android/`, `web/`, etc.
- `firebase_options.dart` and config JSON files are already committed—reuse them instead of regenerating unless credentials rotate.

## Build, Test, and Development Commands
- `make init` installs the pinned Flutter SDK via `fvm` and runs `flutter pub get`.
- `make devices`, `make run-ios`, and `make run-android` list or launch simulators with the expected device IDs; adjust the Makefile only if your emulator names differ.
- `make build` produces Android APKs and iOS artifacts; run before tagging releases.
- `make test`, `fvm flutter test --coverage`, and `fvm flutter analyze` verify correctness and lint status; add `fvm dart format lib test` before committing.
- Use `make clean` and `make pub-get` when caches drift or dependencies change.

## Coding Style & Naming Conventions
- Follow `analysis_options.yaml` + `flutter_lints`; use 2-space indentation, trailing commas for multi-line widget trees, and keep widget constructors const when possible.
- Classes and widgets: `UpperCamelCase`; methods/variables: `lowerCamelCase`; files and directories: `snake_case.dart`.
- Name UI widgets with the suffix `...Widget` or a feature-specific noun (e.g., `TagBattlePage`), and keep private members prefixed with `_`.

## Testing Guidelines
- Each public class/function in `lib/` should have a sibling `*_test.dart` under `test/feature/...`.
- Prefer `testWidgets` for presentation code and standard `test` for core/data layers; mock Firebase interactions with `firebase_core` test utilities or fakes.
- Keep Arrange–Act–Assert blocks explicit and document edge cases in the test name, e.g., `shouldReturnTaggedPlayer_whenTimerExpires`.
- Run `make test` (or `fvm flutter test --coverage`) locally before opening a PR; target >80% coverage on new modules.

## Commit & Pull Request Guidelines
- Use Conventional Commit prefixes (`feat:`, `fix:`, `docs:`) as seen in git history, keep summaries under ~72 chars, and describe scope in English or concise Japanese.
- Squash WIP commits before review; reference issues via `refs #123` or `closes #123` in the body.
- PR descriptions must include: purpose, implementation notes, testing evidence (`make test` output, emulator screenshots for UI), and any follow-up tasks.
- Ensure Firebase keys or service files are not replaced unless coordinated; mention security-sensitive changes explicitly in the PR checklist.
