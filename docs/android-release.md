# Android releases

Journal is distributed from the public `lewiseman/qvac_hack` GitHub repository.
The ARM64 download URL is:

<https://github.com/lewiseman/qvac_hack/releases/latest/download/journal-arm64-v8a.apk>

Every published release contains `journal-arm64-v8a.apk`, its `.sha256` file,
and `release.json`. Identical `journal.apk` and `journal.apk.sha256` compatibility
copies preserve the original permanent download links; download only one APK.
The APK includes the native QVAC runtime and its license notices;
AI model weights download separately. This build supports **Android 10+ on
64-bit ARM phones (arm64-v8a)**.

## ABI splits and download size

The script uses `--split-per-abi --target-platform=android-arm64`. The current
QVAC/BareKit native runtime supports ARM64 only, so the build deliberately emits
one supported split. ARM32 and x86_64 packages would be missing the AI runtime;
the Gradle configuration rejects those split targets while QVAC is enabled.

The first release was already ARM64-only. ABI splitting alone cannot remove
more architectures from it. To reduce direct GitHub downloads, Gradle now
compresses native `.so` libraries (`packaging.jniLibs.useLegacyPackaging = true`).
Android extracts those libraries during installation. The transfer is smaller,
but installed storage includes both the compressed APK and extracted libraries;
this does not reduce the native runtime's memory use or model download sizes.
The verified 0.1.1 build is **126.1 MB**, versus **333.5 MB** for 0.1.0
(**62.2% smaller**). All 55 native libraries have identical uncompressed contents.

The script passes
`--android-project-arg=force-version-code-ignoring-abi=true` so Flutter's default
per-ABI version-code offset does not change Journal's build-number scheme.
For example, `0.1.1+3` stays Android version code **3** and updates `0.1.0+2`.
Artifact validation checks the actual version code, architecture, signature,
and that every packaged native library is compressed.

## Native worklets in release builds

Release R8 optimization preserves the optional worklet registration methods,
the distinct People plugin class, and BareKit's JNI classes/callbacks through
`android/app/barekit-rules.pro`, applied by `qvac.gradle` when BareKit is bundled.
Keep these rules when updating the adapter or runtime; a debug build does not
exercise this shrinking boundary. Registration failures log only the feature
and exception type under `JournalWorklet` (`adb logcat -s JournalWorklet`).

## Local prerequisites

- Flutter matching `pubspec.lock` (currently Flutter 3.47.5 / Dart 3.13.4).
- Node 24.9+ and npm, Python 3.9+, Git, and an Android SDK with Build Tools.
- A JDK. On macOS the script uses Android Studio's bundled JDK when `JAVA_HOME`
  is unset; elsewhere configure `JAVA_HOME` and your `PATH`.
- The existing, ignored `env.json` with `GOOGLE_SERVER_CLIENT_ID` and optionally
  `GOOGLE_CLIENT_ID`. Use the OAuth clients for `com.lewiseman.journal` and the
  **release signing certificate**, including its SHA-1 in Google Cloud's Android
  OAuth client. Test Google sign-in on a phone with the release APK.
- The existing, ignored `android/key.properties`, with `storeFile`,
  `storePassword`, `keyAlias`, and `keyPassword`. Relative keystore paths are
  relative to `android/app/`, as in the Gradle configuration. Back up this
  keystore and its passwords privately; **keep using the same key for updates**.
- For publishing: GitHub authentication via `GH_TOKEN` / `GITHUB_TOKEN`,
  `gh auth login`, or the configured Git credential helper. A fine-grained token
  needs **Contents: read and write** for `lewiseman/qvac_hack` and read access to
  `lewiseman/journal`, where the built commit must be pushed. The script uses the
  GitHub API directly, so installing `gh` is optional.

Never commit the keystore, `key.properties`, tokens or `env.json`. Build output
is ignored under `build/`. The script never bundles those configuration files
as release assets.

## Prepare a build

From the `journal/` checkout:

```sh
python3 scripts/release_android.py
```

This reads the version from `pubspec.yaml`, runs the app and sync tests,
reinstalls the locked native dependencies, rebuilds QVAC for Android, and builds
a signed ARM64 split APK with `env.json`. It verifies the signature, rejects the
Android debug key, checks package/version/architecture, and calculates SHA-256.

Output goes to `build/releases/vVERSION+BUILD/`. If the sibling `bookflip/`
checkout is available, its `src/release.json` is refreshed with the actual APK
size, version and checksum. Use `--site-dir /path/to/bookflip` for another
location. Deploy the marketing update **after** publishing the matching APK.

For a build with a version override without editing `pubspec.yaml`:

```sh
python3 scripts/release_android.py --version 0.1.2+4
```

Native resources and the APK are always rebuilt; an old APK is never uploaded
by mistake. A build made from uncommitted source is permitted for local review,
but publishing requires a clean, pushed app commit.

## Publish the next update

1. Set `version: 0.1.2+4` in `pubspec.yaml`. **Always increase the number after
   `+`**: Android uses it to determine whether an APK is an update.
2. Commit the app changes and push the current branch to GitHub.
3. Run:

   ```sh
   python3 scripts/release_android.py --publish
   ```

The script verifies that the exact source commit exists on GitHub, then builds
and verifies the APK. It creates a draft tagged `v0.1.2+4`, uploads the APK,
checksum, compatibility copies and public metadata, and publishes it as **Latest**
only when all five uploads succeed. An interrupted upload leaves a draft; rerun the same
command from the same commit to retry. Published versions are never overwritten.
The build number must exceed the last published build, and the signing
certificate must match, so existing users can install the update.

For custom release notes, add `--notes-file /path/to/notes.md`.

4. Review the generated change in `../bookflip/src/release.json`, then commit and
   push the marketing checkout to deploy through its existing hosting setup.
   Check locally with:

   ```sh
   cd ../bookflip
   npm run build
   ```

The landing page's download buttons keep the same latest-release URL across
updates; no per-version URL edits are needed. The footer links to installation
instructions and release history.

## Install and verify

Download `journal-arm64-v8a.apk` from the website or GitHub release and open it on an
Android phone. If prompted, allow installation from the browser or file manager.
Install later versions over the existing app to retain its local journal; do
not uninstall first. A development APK signed with a different key cannot be
updated by a release APK.

Download the checksum alongside the APK and run:

```sh
shasum -a 256 -c journal-arm64-v8a.apk.sha256
```

The script verifies build/signature metadata and automated behavior. Actual
installation, Google OAuth, Google Drive sync and device AI still need a
release-device smoke test. OAuth client IDs are compiled into the app, as Android
OAuth requires; keystore credentials and GitHub tokens stay on the build machine.

References: [Flutter Android distribution](https://docs.flutter.dev/deployment/android),
[Android native-library packaging](https://developer.android.com/reference/tools/gradle-api/8.1/com/android/build/api/variant/JniLibsApkPackaging),
[GitHub Releases API](https://docs.github.com/en/rest/releases/releases).
