"""Offline checks for publishing boundaries and Android artifact validation."""
import hashlib
from pathlib import Path
import tempfile
import unittest
import zipfile
from unittest.mock import patch

import release_android as release


class FakeGitHub:
    def __init__(self, existing=None, fail_upload=False):
        self.existing = existing
        self.fail_upload = fail_upload
        self.events = []

    def api(self, method, endpoint, data=None, **kwargs):
        self.events.append((method, endpoint, data))
        if endpoint.startswith("releases/tags/"):
            return self.existing
        if endpoint.startswith("git/ref/tags/"):
            return None
        if method == "POST":
            return {"id": 12}
        if endpoint == "releases/12/assets?per_page=100":
            return []
        if method == "PATCH":
            return {"id": 12, "html_url": "https://github.com/lewiseman/journal/releases/tag/v0.1.0+2"}
        if endpoint == "releases/latest":
            return {"id": 12, "assets": [{"name": event[1]} for event in self.events if event[0] == "UPLOAD"]}
        raise AssertionError((method, endpoint))

    def upload(self, release_id, file):
        self.events.append(("UPLOAD", file.name, None))
        if self.fail_upload:
            raise release.ReleaseError("Upload interrupted")
        return {"size": file.stat().st_size, "state": "uploaded"}


class ReleaseTests(unittest.TestCase):
    def test_versions(self):
        self.assertEqual(release.parse_version("0.1.2+13"), ("0.1.2", 13))
        for value in ("1.2.3", "1.2.3+0", "1.2.3+-1", "v1.2.3+1", "01.2.3+1",
                      "1.2.3+2100000001", "1.2.3+1; echo unsafe", "1.2.3+1\n"):
            with self.subTest(value=value), self.assertRaises(release.ReleaseError):
                release.parse_version(value)

    def test_apk_metadata_and_hash(self):
        signature = "Signer #1 certificate SHA-256 digest: abc123\n"
        badging = ("package: name='com.lewiseman.journal' versionCode='2' versionName='0.1.0'\n"
                   "sdkVersion:'29'\nnative-code: 'arm64-v8a'\n")
        with tempfile.TemporaryDirectory() as directory:
            apk = Path(directory) / "journal.apk"
            with zipfile.ZipFile(apk, "w", compression=zipfile.ZIP_DEFLATED) as archive:
                archive.writestr("lib/arm64-v8a/libfixture.so", b"native library fixture" * 50)
            with patch.object(release, "run", side_effect=[signature, badging]):
                info = release.inspect_apk(apk, Path(directory), "0.1.0", 2)
            self.assertEqual(info["sha256"], hashlib.sha256(apk.read_bytes()).hexdigest())
            self.assertEqual(info["architectures"], ["arm64-v8a"])
            self.assertEqual(info["minSdk"], 29)
            self.assertTrue(info["nativeLibraryCompression"])
            self.assertEqual(info["sizeBytes"], apk.stat().st_size)
            for invalid in (badging.replace("versionCode='2'", "versionCode='1'"),
                            badging.replace("com.lewiseman.journal", "com.other.app"),
                            badging.replace("'arm64-v8a'", "'arm64-v8a' 'x86_64'")):
                with self.subTest(badging=invalid), patch.object(release, "run", side_effect=[signature, invalid]):
                    with self.assertRaises(release.ReleaseError):
                        release.inspect_apk(apk, Path(directory), "0.1.0", 2)
            with zipfile.ZipFile(apk, "w", compression=zipfile.ZIP_STORED) as archive:
                archive.writestr("lib/arm64-v8a/libfixture.so", b"uncompressed native library")
            with patch.object(release, "run", side_effect=[signature, badging]):
                with self.assertRaisesRegex(release.ReleaseError, "must be compressed"):
                    release.inspect_apk(apk, Path(directory), "0.1.0", 2)

    def test_debug_key_is_rejected(self):
        with patch.object(release, "run", return_value="Signer #1 certificate DN: CN=Android Debug, O=Android"):
            with self.assertRaisesRegex(release.ReleaseError, "debug key"):
                release.inspect_apk(Path("unused.apk"), Path("tools"), "0.1.0", 2)

    def test_published_releases_are_never_replaced(self):
        client = FakeGitHub(existing={"draft": False})
        with self.assertRaisesRegex(release.ReleaseError, "already published"):
            release.publish(client, "v0.1.0+2", "sha", [], "notes")
        self.assertEqual(len(client.events), 1)

    def test_wrong_draft_source_is_rejected(self):
        client = FakeGitHub(existing={"draft": True, "target_commitish": "other"})
        with self.assertRaisesRegex(release.ReleaseError, "different commit"):
            release.publish(client, "v0.1.0+2", "sha", [], "notes")
        self.assertEqual(len(client.events), 1)

    def test_existing_tag_must_match_the_built_source(self):
        client = FakeGitHub()
        with patch.object(client, "api", side_effect=[None, {"object": {"type": "commit", "sha": "other"}}]):
            with self.assertRaisesRegex(release.ReleaseError, "different source"):
                release.publish(client, "v0.1.0+2", "sha", [], "notes")

    def test_publish_only_after_every_upload_completes(self):
        with tempfile.TemporaryDirectory() as directory:
            files = [Path(directory) / name for name in ("journal.apk", "journal.apk.sha256", "release.json")]
            for file in files:
                file.write_text("fixture")
            client = FakeGitHub()
            release.publish(client, "v0.1.0+2", "sha", files, "notes")
            actions = [event[0] for event in client.events]
            created = next(event for event in client.events if event[0] == "POST")
            self.assertTrue(created[2]["draft"])
            self.assertEqual(actions.count("UPLOAD"), 3)
            self.assertLess(max(i for i, a in enumerate(actions) if a == "UPLOAD"), actions.index("PATCH"))
            self.assertFalse(client.events[actions.index("PATCH")][2]["draft"])
            interrupted = FakeGitHub(fail_upload=True)
            with self.assertRaisesRegex(release.ReleaseError, "interrupted"):
                release.publish(interrupted, "v0.1.0+2", "sha", files, "notes")
            self.assertNotIn("PATCH", [event[0] for event in interrupted.events])


if __name__ == "__main__":
    unittest.main()
