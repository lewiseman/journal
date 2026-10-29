# On-device AI verification — 29 October 2026

Implementation and removal instructions: [on-device-ai.md](on-device-ai.md).
The diagnostic target uses synthetic prompts and never opens the notes/account
ObjectBox stores. The normal Journal app was restored on the physical phone.

## Automated checks

- Full Flutter unit/widget suite: **652 passed**, run with `--concurrency=1`.
- Focused local AI suite: **46 passed** (included in the full count).
- Desktop suite: **128 passed**, including deterministic export/staleness tests.
- Changed production files, tests and diagnostic target: clean Flutter analysis.
- Full-project analysis still encounters the pre-existing undefined
  `LocalDiarySearchService` reference at
  `integration_test/diary_history_device_test.dart:278`; this file was not changed.
- Native build: SDK/core 0.22.0; BareKit 2.5.5 V8 archive SHA-256 verified.
- Android APK metadata: **arm64-v8a only**, **minSdk 29**.
- iOS arm64 simulator: complete app builds; worklet ping and shutdown pass.
  The relay is present in the compiled binary and actually registers its channels.

## Physical Android

Device: Samsung SM S928B, Android 17 / API 37, reported RAM 11,622,989,824 bytes.

Passed:

- Qwen2.5 0.5B GGUF downloaded over Wi-Fi and verified against its pinned size
  and SHA-256; local model loaded through the bundled worklet.
- Actual token streaming, cancellation after the first token, graceful shutdown,
  and a fresh worklet restart.
- Airplane-mode summary and rewrite through `OperationRunner`, with the exported
  desktop prompts and existing Dart output contracts. Airplane mode and Wi-Fi
  were restored to their initial values (**0** and **1**, respectively).
- A too-large catalog model returned `RESOURCE` with “This model needs more
  memory. Choose a smaller model.” before opening weights; no crash.
- Backgrounding a running image job at step 2/20 reported `interrupted` and
  cancelled the worklet. Returning to the app did not resume or rerun the job.
- Actual `generate-note-background` job: progress, **256 × 384 PNG**, **273,498
  bytes**, seed **76,972,368**, matching PNG dimensions and SHA-256 metadata,
  result collection, acknowledgment and cleanup.

The image weights were copied from the desktop's existing pinned SD 2.1 file
via USB and verified on the phone, avoiding a second 2.32 GB download.

The Android Vulkan addon aborted inside quantized matrix kernels in both text
encoding and UNet execution. OpenCL returned a clean model-load error. The
shipping Android configuration therefore uses CPU with VAE tiling; iOS retains
Metal. CPU image generation takes several minutes in this debug target. The
phone preset (256 × 384, 12 steps) lives in the desktop source and is exported
with the operation data. Runtime hashes of unchanged private model files are
cached for the current process; a changed file or app restart requires hashing.

Sampled Android image-test peak PSS: **2,902,971 KiB (2.77 GiB)**, from `dumpsys
meminfo` at two-second intervals. This is a sampled debug-process measurement,
not a guaranteed peak or a substitute for release profiling.

## iOS simulator

On the arm64 iPhone 17 Pro simulator, the Swift relay loaded Qwen 0.5B from a
local pinned file, streamed real tokens, cancelled a native completion, and
produced valid summary/rewrite outputs through the Dart runner. No model download
or Journal account/notes access was needed. This supplements the build and ping
checks; it does not replace physical iOS validation.

## Removal drill and package growth

QVAC Dart/build/native folders were deleted in an isolated copy; registration
and generated Xcode links were removed and the registry returned null.
Android debug and iOS simulator builds passed. UI tests confirmed that phone
setup hides, saved device-mode preferences require an explicit Companion choice,
and a replacement fake engine works. Retained local handles resolve as
interrupted/cancelled without any remote request.

Comparable arm64 debug APKs (normal app target):

| Build | Bytes | Decimal MB |
| --- | ---: | ---: |
| Companion only | 176,841,348 | 176.84 |
| With QVAC | 481,971,774 | 481.97 |
| Growth | 305,130,426 | 305.13 |

Uncompressed iOS arm64 simulator app bundles (normal app target):

| Build | Bytes | Decimal MB |
| --- | ---: | ---: |
| Companion only | 260,397,061 | 260.40 |
| With QVAC | 412,820,091 | 412.82 |
| Growth | 152,423,030 | 152.42 |

Weights are outside the app bundle. These measurements include debug runtimes
and are **not release APK or signed IPA size estimates**. The pinned native
prebuilds include multiple GPU backends even though Android currently uses CPU.

## Before distribution

Measure release APK/signed IPA size and profile peak memory on target hardware.
Physical iOS inference and image generation, iOS background interruption, and
image cancellation from the finished feature UI still need device coverage.
The iOS increased-memory-limit entitlement has not been enabled without that
profiling. Vision/OCR and voice remain companion-only.

`HF_TOKEN` was removed from mobile `env.json`. Revoke/rotate the old credential
in the Hugging Face account; local removal cannot invalidate previous copies.
