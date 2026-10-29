# On-device AI

Journal owns AI operations in Dart. A provider is selected when a task starts;
accepted jobs retain that provider in `SummaryHandle.provider` (old ObjectBox
metadata and secure handles default to `companion`). Changing modes never moves
accepted work or silently retries it on another machine.

## Boundaries and behavior

`OnDeviceEngine` is the replacement seam: lifecycle, model files, completion
messages/parameters/schema, cancellable token events, and image progress/bytes.
It has no note, diary, operation, prompt, credential or download concepts.
`engine_registry.dart` is the only application file importing an implementation.
A null registration hides the phone controls and leaves companion features intact.

The default remains Companion. Auto prefers a connected companion; otherwise it
uses a compatible assigned phone model. Per-task Companion / On this phone
choices override the overall mode. An unavailable explicit choice produces an
error and never changes destination. Vision, OCR, websites and voice stay on the
companion for this rollout. Phone writing supports summaries, transformations,
note metadata/ideas/templates, diary suggestions/questions/answers, saved-note
and Flow questions, and Flow reflections. Background generation uses SD 2.1. The phone requests a 256 × 384 portrait with 12 steps to keep CPU generation practical; these defaults are exported from the desktop source alongside the shared prompts.

The Local AI page leads with the selected provider's setup. The other provider
stays in a collapsed section; opening it does not change where tasks run. Auto
leads with Companion when connected, otherwise phone setup. Per-task exceptions
and engine details live under Advanced, with a visible count of custom choices.
Phone setup calls out that search by meaning, voice and scans still need the
companion. Writing/image download shortcuts open a catalog filtered to that task.

Phone jobs run only in the foreground, one model/job at a time. Native relays
suspend on backgrounding; Dart cancels and cleans up the worklet and reports the
job as interrupted. Output is validated by the existing Dart feature contracts.
Prompts/results are held in memory for at most 24 hours and acknowledged results
are discarded. Acceptance metadata and input hashes are atomically persisted outside backups before inference starts, including when the acceptance reply is lost. A process restart retains the protected feature receipt but marks
an accepted phone job interrupted, never resubmitting its prompt. The companion
retains its existing durable recovery behavior.

## Prompts and models

From `desktop/`:

```sh
npm run export:operations
npm run verify:operations
npm test
```

`src/*` prompt modules are authoritative. The exporter writes
`journal/assets/ai/operations.json` and `models.json`, including system messages,
limits, response schemas, generation parameters, image styling and pinned model
metadata. `npm test` verifies freshness before running tests. Schemas are data;
operation/message construction and output validation stay in Dart.

The catalog uses public pinned GGUF repositories, exact byte counts, SHA-256,
license and minimum RAM. SD 2.1 Q8_0 is **2,322,705,024 bytes**, not 1.6 GB.
Assignments only accept models matching the task and engine formats. Model loads
check RAM and verify file size/hash before native code sees a local path. Verified
private files reuse their digest in the current process only while size, mtime
and ctime stay unchanged; changed files and app restarts require hashing again.

Downloads resume `.partial` files using Range; a server ignoring Range replaces
the partial rather than appending. Invalid ranges, sizes, compression and
checksums fail closed. Cancel keeps partial bytes; Manage models offers Resume and Discard partial download. Disk reserve is 100 MiB and
Wi-Fi only is the default; cellular handoff pauses the transfer. Android uses
`noBackupFilesDir/ai_models`; iOS uses Application Support with
`isExcludedFromBackup`. This storage/resource channel is independent of QVAC.

There is no shared Hugging Face token in mobile code or model requests.
`HF_TOKEN` was removed from mobile `env.json`. **Revoke/rotate the previous token
in the Hugging Face account**; deleting a local key cannot revoke copies already
compiled into earlier binaries. Gated models remain a companion concern; no
mobile token entry is needed for this public catalog.

## Build QVAC / BareKit

Requirements: Node ^22.21 or >=24.9, Flutter, Android SDK; macOS/Xcode and the
CocoaPods `xcodeproj` Ruby gem for iOS wiring.

```sh
cd journal/native/qvac
npm ci --ignore-scripts
npm run build
```

The build pins SDK and in-process core **0.22.0**, bare-pack 2.0.1, bare-link 4.0.1,
and BareKit **2.5.5 V8**. It runs `bundleSdk` for ios-arm64,
ios-arm64-simulator and android-arm64, then packs our primitive entry and runs
bare-link. BareKit's archive must match
`fc68740347c8532ba49d45bf61fae9ca1f1040dc7d6c99f2f92dc30c40e84e46`.
Outputs are restricted to QVAC-owned folders. No model weights or downloaded
executable code enter runtime downloads. `qvac/licenses` collects package notices.

The build detects standard Homebrew CocoaPods GEM_HOME wrappers. If Ruby cannot find `xcodeproj`, set `QVAC_RUBY` to the
Homebrew Ruby executable and `QVAC_GEM_HOME` to CocoaPods' `libexec` directory.
The build's `wire-ios.rb` creates a single removable Qvac Xcode group with the
source, bundle, linked/embedded frameworks. Run the native build before Flutter
packaging: generated binaries are intentionally ignored by Git.

Android requires API 29 and arm64-v8a when the QVAC resources exist. The separate
`qvac.gradle` supplies those constraints, assets, JAR and JNI paths. iOS 15 is
sufficient for these pinned artifacts (confirmed by an arm64 simulator build and
native load-command metadata). Intel simulators are unsupported. The increased
memory entitlement is deliberately not enabled without physical iOS memory
profiling; start with the 0.5B model, and measure larger models on target hardware.

On Android the image engine explicitly runs on CPU with VAE tiling. The pinned
Vulkan addon aborted inside quantized matrix kernels on the test phone; OpenCL
returned a clean model-load error. CPU selection is inside the adapter and does
not change feature logic or provider routing. iOS keeps the Metal/GPU path.


The worklet uses the SDK's public `@qvac/inference` in-process core. It avoids
`worker-lifecycle`, whose process-exit handlers are inappropriate inside a mobile
app. Our primitive RPC server handles uncaught exceptions without calling
`Bare.exit`. Both native relays serialize writes, buffer early output, pass
`HOME_DIR` as argv[2], suspend in background and resume for cleanup. Dart sends
`__shutdown__` and waits for cleanup before terminating BareKit, including after
a hot restart.

## Remove or replace QVAC

1. Before deleting the build tools, run `ruby native/qvac/wire-ios.rb "$PWD" --remove`
   with the same Ruby/GEM_HOME used to build. This removes generated Xcode links.
2. Remove the QVAC import and factory in `engine_registry.dart`; set the engine to
   null, or register another `OnDeviceEngine`.
3. Delete `lib/modules/local_ai/engines/qvac/` and `native/qvac/`.
4. Delete `android/app/src/qvac/`, `android/app/qvac.gradle`, and
   `android/app/src/main/kotlin/com/lewiseman/journal/qvac/` (the Kotlin relay is a
   source folder separate from generated resources).
5. Delete `ios/Runner/Qvac/` and `ios/Frameworks/Qvac/`.
6. Remove the registration line from `MainActivity.kt` and `AppDelegate.swift`,
   and the apply line in `android/app/build.gradle.kts`. Keep `LocalAiStorage`.
7. Remove adapter-specific `bare_rpc_test.dart` and the optional
   `tool/local_ai_spike.dart` diagnostic target.

No feature, router, catalog, downloader or settings UI needs to change. Saved device-mode choices show an explicit Companion recovery action, and retained local jobs become interrupted without remote submission. The
architecture test forbids implementation imports outside the registry. A removal
drill was performed in an isolated copy: Android debug and iOS simulator builds
passed and the empty-registry UI test hid phone setup.

## Verification

```sh
flutter test test/local_ai
flutter test
flutter analyze lib/modules/local_ai
flutter run -d <physical-arm64-device> -t tool/local_ai_spike.dart
# Reuses installed weights; never initiates a model download:
flutter run -d <physical-arm64-device> -t tool/local_ai_spike.dart --dart-define=AI_SPIKE_OFFLINE=true
```

The diagnostic target does not open the app's account, notes or ObjectBox data.
It tests a real bundled worklet, SHA-256 weights, streamed completion, native
cancellation, app-operation validation, cleanup and restart. Its background
stage exposes `BACKGROUND_TEST_READY` for sending the app to Home and returning;
expect `BACKGROUND_TEST_RESULT interrupted`.

Unit tests cover routing choices/overrides, empty registries, engine-independent
operation messages and output contracts, RPC frame splits and stream handshakes,
Range resume/ignored ranges/checksum/cancel/network/disk failures, idempotent jobs,
cancel/interruption/concurrency, and a narrow-screen settings selector.

Physical Android verification and outstanding release checks are recorded in
`on-device-ai-verification.md`. Debug package sizes are measurements, not release
APK/IPA size predictions. Profile release builds before shipping and exercise
SD generation, peak memory, switching, and background behavior on each device
family.
