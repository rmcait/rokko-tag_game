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

## API Integration Guidelines
- Base URL is `https://api.tag-game.example.com/v1`; every HTTP call must include `Authorization: Bearer <Firebase ID token>` issued by Firebase Auth (Google Sign-In flow). Reuse the RFC7807-style error envelope from `api.md` when surfacing backend failures to the UI.
- User bootstrap flow: call `POST /users` right after sign-in to provision the profile (optionally sending `displayName`, `avatarUrl`, `fcmToken`), then fetch session context via `GET /users/me`; keep profile updates scoped to `PATCH /users/me`.
- Party lifecycle endpoints (`POST /parties`, `/join`, `/leave`, `/roles/assign`, `/start`) enforce a hard cap of 5 members and `durationMinutes` in `[5,15,30,60]`. Handle HTTP 409 to show “満員 / 進行中” states in the client and surface `freezeUntil` timestamps when roles are assigned.
- During games, stream player telemetry with `POST /games/{gameId}/locations` every 1–5 seconds; treat 422 as an out-of-bounds signal and fall back to the sync endpoint `GET /games/{gameId}/sync` after reconnection gaps >10 seconds.
- Abilities and items each have their own dedicated endpoints (`/abilities/listen`, `/fake-location`, `/freeze-tagger`, `/trap-trigger`, `/freeze-all`, `/items/{itemId}/pickup`, etc.). Respect cooldowns/gauge values returned by the server instead of deriving them on-device, and propagate `visibleRunners`, `effect`, or `durationSeconds` payloads straight into in-game overlays.
- Use the WebSocket channel `/ws/games/{gameId}` to react to `PLAYER_JOINED`, `ROLE_ASSIGNED`, `ITEM_SPAWNED`, `TAG_EVENT`, etc.; fall back to `GET /games/{gameId}` for cold starts or missed pushes.

## Database & Data Integrity
- Firestore (native mode) stores the authoritative game state described in `database.md`: `users`, `parties` (+`members` subcollection), and `gameSessions` with `players`, `items`, `events`. Cloud Storage keeps avatars/binary assets, and Cloud Functions enforce transactional logic.
- Always treat `users.userId`, `parties.partyId`, and `gameSessions.gameId` as `usr_`, `par_`, `gam_` prefixed IDs; UI code should never mint them locally. Reference links (`parties.ownerId`, `gameSessions.partyId`, `players.userId`) must stay consistent with these IDs.
- Respect collection-specific statuses: `parties.status` (`WAITING/READY/IN_PROGRESS/FINISHED/CANCELLED`) and `gameSessions.status` (`PREPARE/ACTIVE/ENDED/ABORTED`). Client transitions (e.g., enabling the Start button) should mirror these values rather than local heuristics.
- Player documents (`gameSessions/{gameId}/players`) expose `gauge`, `cooldowns`, `items`, and `status` (`ACTIVE`, `CAUGHT`, `DISCONNECTED`). Update flows should go through Cloud Functions, but the app must display these fields read-only when rendering HUD components.
- Indexed queries to keep in mind: lobby screens use `parties.status` + `updatedAt desc`, active sessions use `gameSessions.status` + `updatedAt desc`, and player lists filter by `status` + `role`. Any new queries should reuse these patterns or add matching composite indexes.
- Data retention: `gameSessions` (and children) are purged 30 days post-game after shipping summaries to BigQuery. Features that show history must read from the API layer (`GET /users/me/history` once implemented) rather than expecting old Firestore documents to persist indefinitely.
