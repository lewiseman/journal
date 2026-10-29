#!/usr/bin/env python3
"""Build a signed Journal APK and optionally publish it to GitHub Releases.

Uses Python's standard library, Flutter, Node/npm and the Android SDK. Credentials
stay local: env.json and android/key.properties are never copied into artifacts.
"""

import argparse
import hashlib
import http.client
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = "lewiseman/journal"
APK_NAME = "journal-arm64-v8a.apk"
DOWNLOAD_URL = f"https://github.com/{REPOSITORY}/releases/latest/download/{APK_NAME}"
LEGACY_DOWNLOAD_URL = f"https://github.com/{REPOSITORY}/releases/latest/download/journal.apk"


class ReleaseError(Exception):
    pass


def run(*args, cwd=ROOT, capture=False):
    result = subprocess.run(args, cwd=cwd, text=True, check=True,
                            stdout=subprocess.PIPE if capture else None)
    return result.stdout.strip() if capture else None


def parse_version(value):
    match = re.fullmatch(r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)\+([1-9]\d*)", value)
    if not match or int(match[4]) > 2_100_000_000:
        raise ReleaseError("Version must be MAJOR.MINOR.PATCH+BUILD, e.g. 0.1.1+3 (BUILD: 1–2100000000).")
    name, number = value.split("+")
    return name, int(number)


def github_token():
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if token:
        return token
    if shutil.which("gh"):
        result = subprocess.run(["gh", "auth", "token", "--hostname", "github.com"],
                                capture_output=True, text=True)
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip()
    result = subprocess.run(["git", "credential", "fill"], cwd=ROOT,
                            input="protocol=https\nhost=github.com\n\n",
                            capture_output=True, text=True,
                            env={**os.environ, "GIT_TERMINAL_PROMPT": "0"})
    fields = dict(line.split("=", 1) for line in result.stdout.splitlines() if "=" in line)
    if fields.get("password"):
        return fields["password"]
    raise ReleaseError("GitHub login required: run gh auth login, configure Git credentials, or set GH_TOKEN with Contents: write.")


class GitHub:
    def __init__(self, token):
        self.headers = {"Authorization": f"Bearer {token}",
                        "Accept": "application/vnd.github+json",
                        "X-GitHub-Api-Version": "2022-11-28",
                        "User-Agent": "Journal-release"}

    def api(self, method, endpoint, data=None, missing_ok=False):
        payload = json.dumps(data).encode() if data is not None else None
        request = urllib.request.Request(f"https://api.github.com/repos/{REPOSITORY}/{endpoint}",
                                         data=payload, method=method,
                                         headers={**self.headers, "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                return json.load(response) if response.status != 204 else None
        except urllib.error.HTTPError as error:
            if error.code == 404 and missing_ok:
                return None
            raise ReleaseError(f"GitHub {method} {endpoint} failed (HTTP {error.code}).") from error

    def upload(self, release_id, file):
        # Stream large APKs; never send the bearer token through a redirected URL.
        connection = http.client.HTTPSConnection("uploads.github.com", timeout=600)
        endpoint = f"/repos/{REPOSITORY}/releases/{release_id}/assets?name={urllib.parse.quote(file.name)}"
        try:
            with file.open("rb") as stream:
                connection.request("POST", endpoint, body=stream,
                                   headers={**self.headers, "Content-Type": "application/octet-stream",
                                            "Content-Length": str(file.stat().st_size)})
                response = connection.getresponse()
                payload = response.read()
            if response.status != 201:
                raise ReleaseError(f"Uploading {file.name} failed (HTTP {response.status}); the release remains a draft.")
            return json.loads(payload)
        finally:
            connection.close()


def android_tools():
    sdk = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
    if not sdk:
        properties = ROOT / "android/local.properties"
        if properties.exists():
            match = re.search(r"^sdk.dir=(.+)$", properties.read_text(), re.M)
            sdk = match[1].replace("\\:", ":").replace("\\\\", "\\") if match else None
    if not sdk:
        raise ReleaseError("Set ANDROID_HOME or sdk.dir in android/local.properties.")
    versions = [p for p in (Path(sdk) / "build-tools").glob("*")
                if (p / "apksigner").is_file() and (p / "aapt").is_file()]
    if not versions:
        raise ReleaseError("Install Android SDK Build Tools (apksigner and aapt are required).")
    return max(versions, key=lambda p: tuple(int(x) for x in re.findall(r"\d+", p.name)))


def inspect_apk(apk, tools, version_name, build_number):
    signature = run(str(tools / "apksigner"), "verify", "--verbose", "--print-certs", str(apk), capture=True)
    if "CN=Android Debug" in signature:
        raise ReleaseError("Refusing to distribute an APK signed with the Android debug key.")
    certificate = re.search(r"Signer #1 certificate SHA-256 digest: (\S+)", signature)
    badging = run(str(tools / "aapt"), "dump", "badging", str(apk), capture=True)
    package = re.search(r"^package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'", badging, re.M)
    if not package or package.groups() != ("com.lewiseman.journal", str(build_number), version_name):
        raise ReleaseError("APK package ID or version does not match the requested release.")
    sdk = re.search(r"^sdkVersion:'(\d+)'", badging, re.M)
    native = re.search(r"^native-code: (.+)$", badging, re.M)
    if not sdk or not native or not certificate:
        raise ReleaseError("Could not verify APK platform requirements or signing certificate.")
    abis = re.findall(r"'([^']+)'", native[1])
    if abis != ["arm64-v8a"]:
        raise ReleaseError(f"Expected the QVAC Android arm64 build, got {abis}.")
    with zipfile.ZipFile(apk) as archive:
        libraries = [entry for entry in archive.infolist()
                     if entry.filename.startswith("lib/") and entry.filename.endswith(".so")]
        if not libraries or any(entry.compress_type != zipfile.ZIP_DEFLATED for entry in libraries):
            raise ReleaseError("Native libraries must be compressed for the direct-download APK.")
    hasher = hashlib.sha256()
    with apk.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            hasher.update(chunk)
    return {"sizeBytes": apk.stat().st_size, "sha256": hasher.hexdigest(),
            "minSdk": int(sdk[1]), "architectures": abis, "nativeLibraryCompression": True,
            "signingCertificateSha256": certificate[1]}


def publish(client, tag, source_commit, files, notes):
    release = client.api("GET", f"releases/tags/{urllib.parse.quote(tag, safe='')}", missing_ok=True)
    if release and not release["draft"]:
        raise ReleaseError(f"{tag} is already published. Increase the build number; published APKs are never replaced.")
    if release and release["target_commitish"] != source_commit:
        raise ReleaseError("The existing draft targets a different commit. Use a new version or resolve that draft first.")
    tag_ref = client.api("GET", f"git/ref/tags/{urllib.parse.quote(tag, safe='')}", missing_ok=True)
    if tag_ref:
        target = tag_ref["object"]
        while target["type"] == "tag":
            target = client.api("GET", f"git/tags/{target['sha']}")["object"]
        if target["type"] != "commit" or target["sha"] != source_commit:
            raise ReleaseError("That Git tag points to different source. Choose a new version; existing tags are never moved.")
    if not release:
        release = client.api("POST", "releases", {"tag_name": tag, "target_commitish": source_commit,
                             "name": f"Journal {tag[1:]}", "body": notes, "draft": True, "prerelease": False})
    # Only draft uploads may be replaced after an interrupted attempt.
    for asset in client.api("GET", f"releases/{release['id']}/assets?per_page=100"):
        if asset["name"] in {file.name for file in files}:
            client.api("DELETE", f"releases/assets/{asset['id']}")
    for file in files:
        asset = client.upload(release["id"], file)
        if asset["size"] != file.stat().st_size or asset["state"] != "uploaded":
            raise ReleaseError(f"GitHub did not confirm the complete upload of {file.name}.")
    release = client.api("PATCH", f"releases/{release['id']}",
                         {"draft": False, "prerelease": False, "make_latest": "true", "body": notes})
    latest = client.api("GET", "releases/latest")
    if latest["id"] != release["id"] or not {file.name for file in files}.issubset({a["name"] for a in latest["assets"]}):
        raise ReleaseError("Release published, but it is not the latest APK release. Check GitHub before deploying the website.")
    print(f"Published: {release['html_url']}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", help="MAJOR.MINOR.PATCH+BUILD; defaults to pubspec.yaml")
    parser.add_argument("--publish", action="store_true", help="Upload a new GitHub release and make it latest; requires clean, pushed source")
    parser.add_argument("--skip-tests", action="store_true", help="Skip Flutter tests when the same source was already tested")
    parser.add_argument("--site-dir", type=Path, default=ROOT.parent / "bookflip", help="Marketing checkout to update after success")
    parser.add_argument("--notes-file", type=Path, help="Optional Markdown release notes")
    args = parser.parse_args()
    match = re.search(r"^version:\s*(\S+)", (ROOT / "pubspec.yaml").read_text(), re.M)
    version = args.version or (match[1] if match else "")
    version_name, build_number = parse_version(version)
    tag = f"v{version}"
    studio_java = Path("/Applications/Android Studio.app/Contents/jbr/Contents/Home")
    if not os.environ.get("JAVA_HOME") and (studio_java / "bin/java").is_file():
        os.environ["JAVA_HOME"] = str(studio_java)
        os.environ["PATH"] = f"{studio_java / 'bin'}{os.pathsep}{os.environ.get('PATH', '')}"
    for command in ("flutter", "node", "npm", "git", "java"):
        if not shutil.which(command):
            raise ReleaseError(f"Required command is missing: {command}.")
    for file in ("env.json", "android/key.properties"):
        if not (ROOT / file).is_file():
            raise ReleaseError(f"Missing {file}; see docs/android-release.md. Never commit signing or OAuth configuration.")
    if not json.loads((ROOT / "env.json").read_text()).get("GOOGLE_SERVER_CLIENT_ID"):
        raise ReleaseError("env.json must include GOOGLE_SERVER_CLIENT_ID for release sign-in.")
    tools = android_tools()
    source_commit = run("git", "rev-parse", "HEAD", capture=True)
    dirty = bool(run("git", "status", "--porcelain", capture=True))
    client = None
    previous_metadata = None
    if args.publish:
        if dirty:
            raise ReleaseError("Commit the app's current changes and push that commit before using --publish. Build-only mode accepts local changes.")
        client = GitHub(github_token())
        client.api("GET", f"commits/{source_commit}")  # Require the exact built source on GitHub.
        existing = client.api("GET", f"releases/tags/{urllib.parse.quote(tag, safe='')}", missing_ok=True)
        if existing and not existing["draft"]:
            raise ReleaseError(f"{tag} is already published; increase BUILD for the next update.")
        latest = client.api("GET", "releases/latest", missing_ok=True)
        if latest:
            previous = client.api("GET", f"releases/{latest['id']}/assets?per_page=100")
            metadata = next((asset for asset in previous if asset["name"] == "release.json"), None)
            if metadata:
                with urllib.request.urlopen(metadata["browser_download_url"], timeout=60) as response:
                    previous_metadata = json.load(response)
                    previous_build = previous_metadata.get("buildNumber", 0)
                if build_number <= previous_build:
                    raise ReleaseError(f"BUILD must exceed the latest release's {previous_build} so Android can install updates.")
    print(f"Building Journal {version} from {source_commit[:12]}" + (" (includes local changes)" if dirty else ""), flush=True)
    run("flutter", "pub", "get")
    if not args.skip_tests:
        run("flutter", "test")
        run("flutter", "test", "packages/sync_wise/test")
    run("npm", "ci", cwd=ROOT / "native/qvac")
    run("npm", "run", "check", cwd=ROOT / "native/qvac")
    run("npm", "run", "build", "--", "--platform=android", cwd=ROOT / "native/qvac")
    run("flutter", "build", "apk", "--release", "--split-per-abi", "--target-platform=android-arm64",
        "--android-project-arg=force-version-code-ignoring-abi=true",
        "--dart-define-from-file=env.json", f"--build-name={version_name}", f"--build-number={build_number}")
    apk = ROOT / "build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
    metadata = {"version": version_name, "buildNumber": build_number, "tag": tag,
                "downloadUrl": DOWNLOAD_URL, "legacyDownloadUrl": LEGACY_DOWNLOAD_URL,
                "artifactName": APK_NAME, "buildType": "split-per-abi", "sourceCommit": source_commit,
                "sourceDirty": dirty, **inspect_apk(apk, tools, version_name, build_number)}
    if client and (run("git", "status", "--porcelain", capture=True)
                   or run("git", "rev-parse", "HEAD", capture=True) != source_commit):
        raise ReleaseError("The build modified tracked source; review, commit and rebuild before publishing.")
    if previous_metadata and previous_metadata.get("signingCertificateSha256") != metadata["signingCertificateSha256"]:
        raise ReleaseError("Signing certificate differs from the latest release. Restore the original release key so users can update.")
    output = ROOT / "build/releases" / tag
    output.mkdir(parents=True, exist_ok=True)
    artifact = output / APK_NAME
    shutil.copy2(apk, artifact)
    checksum = output / f"{APK_NAME}.sha256"
    checksum.write_text(f"{metadata['sha256']}  {APK_NAME}\n")
    # Preserve permanent links from the first release. Both names are the same APK.
    legacy_artifact = output / "journal.apk"
    shutil.copy2(artifact, legacy_artifact)
    legacy_checksum = output / "journal.apk.sha256"
    legacy_checksum.write_text(f"{metadata['sha256']}  journal.apk\n")
    manifest = output / "release.json"
    manifest.write_text(json.dumps(metadata, indent=2) + "\n")
    notes = args.notes_file.read_text() if args.notes_file else (
        f"Journal {version_name} (build {build_number}) for Android.\n\n"
        f"Download **{APK_NAME}** below and open it on your phone. Allow your browser or file manager to install apps if Android asks.\n\n"
        f"- Android API {metadata['minSdk']}+; 64-bit ARM (arm64-v8a).\n"
        f"- Download: {metadata['sizeBytes'] / 1_000_000:.1f} MB.\n"
        "- Built with ABI splitting and compressed native libraries for a smaller download. Android extracts the libraries at install time, using additional device storage.\n"
        "- QVAC currently supports ARM64 only; ARM32 and x86_64 builds are unavailable.\n"
        "- journal.apk is an identical compatibility copy for older download links; download only one APK.\n"
        "- Signed with Journal's existing release key; install future builds over this app to keep your journal.\n"
        "- AI model weights download separately when selected in the app.\n"
        "- Google Drive backup requires Google sign-in.\n\n"
        f"Source: `{source_commit}`.\n\n"
        f"Verify the download with `shasum -a 256 -c {APK_NAME}.sha256`.\n")
    (output / "release-notes.md").write_text(notes)
    print(f"Verified signed APK: {artifact}\nSHA-256: {metadata['sha256']}", flush=True)
    if client:
        publish(client, tag, source_commit, [artifact, checksum, legacy_artifact, legacy_checksum, manifest], notes)
    # Build-only mode prepares the matching marketing change for review too.
    # Publish the APK before deploying these website files.
    if (args.site_dir / "src/site.js").is_file():
        (args.site_dir / "src/release.json").write_text(manifest.read_text())
        print(f"Updated website metadata: {args.site_dir / 'src/release.json'}")
    print(f"Download URL: {DOWNLOAD_URL}")
    if not client:
        print("Build prepared locally. To make it downloadable, commit/push the app source, then rerun with --publish.")


if __name__ == "__main__":
    try:
        main()
    except (ReleaseError, subprocess.CalledProcessError, OSError, ValueError, urllib.error.URLError) as error:
        print(f"Release stopped: {error}", file=sys.stderr)
        sys.exit(1)
