"""Behavioral regression coverage for CI boundaries and interrupted releases."""

import base64
from copy import deepcopy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import android
import checks
from common import apk_name, pubspec_version
import github_release as github
import release
import signing

COMMIT = "a" * 40
CERTIFICATE = "b" * 64
BASELINE = {"version_name": "1.1.5", "version_code": 43}


class ContextTests(unittest.TestCase):
    def test_pr_and_main_never_request_release(self):
        for event, ref in [("pull_request", "refs/pull/1/merge"), ("push", "refs/heads/main")]:
            self.assertFalse(checks.release_requested(event, ref, "release"))

    def test_manual_check_and_tag_release(self):
        self.assertFalse(checks.release_requested("workflow_dispatch", "refs/tags/v1.2.3", "check"))
        self.assertTrue(checks.release_requested("workflow_dispatch", "refs/tags/v1.2.3", "release"))
        self.assertTrue(checks.release_requested("push", "refs/tags/v1.2.3", "check"))

    def test_invalid_refs_and_modes_fail_closed(self):
        for event, ref, mode in [
            ("workflow_dispatch", "refs/heads/main", "release"),
            ("workflow_dispatch", "refs/tags/v01.2.3", "release"),
            ("push", "refs/tags/v1.2.3-beta", "check"),
            ("workflow_dispatch", "refs/heads/main", "unknown"),
            ("pull_request_target", "refs/heads/main", "check"),
        ]:
            with self.subTest(ref=ref), self.assertRaises(ValueError):
                checks.release_requested(event, ref, mode)

    def test_required_check_fails_for_cancelled_skipped_failed_or_missing_job(self):
        results = {name: {"result": "success"} for name in
                   ["quality", "package-tests", "app-tests", "android-check"]}
        checks.gate(results)
        for state in ["failure", "cancelled", "skipped", None]:
            with self.subTest(state=state), self.assertRaises(ValueError):
                checks.gate({**results, "app-tests": {"result": state}})
        del results["android-check"]
        with self.assertRaises(ValueError):
            checks.gate(results)

    def test_changed_files_handle_unicode_spaces_renames_and_deletions(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def git(*args):
                return subprocess.check_output(["git", *args], cwd=root, text=True, encoding="utf-8").strip()
            git("init", "--quiet")
            git("config", "user.name", "CI Fixture")
            git("config", "user.email", "ci@example.invalid")
            (root / "deleted.dart").write_text("old", encoding="utf-8")
            (root / "before.dart").write_text("before", encoding="utf-8")
            git("add", ".")
            git("commit", "--quiet", "-m", "baseline")
            base = git("rev-parse", "HEAD")
            (root / "deleted.dart").unlink()
            (root / "before.dart").rename(root / "改名 with spaces.dart")
            (root / "new.dart").write_text("new", encoding="utf-8")
            (root / "README.md").write_text("docs", encoding="utf-8")
            git("add", ".")
            git("commit", "--quiet", "-m", "change")
            self.assertEqual(set(checks.changed_dart_files(base, cwd=root)),
                             {"改名 with spaces.dart", "new.dart"})

    def test_generated_and_localization_drift_fail(self):
        with patch.object(checks, "run", return_value=""), patch.object(checks, "read_json", return_value={}):
            checks.clean()
        with patch.object(checks, "run", return_value=""), patch.object(checks, "read_json", return_value={"zh": ["missing"]}):
            with self.assertRaises(ValueError):
                checks.clean()
        with patch.object(checks, "run", return_value="lib/generated.dart"):
            with self.assertRaises(ValueError):
                checks.clean()


class VersionTests(unittest.TestCase):
    def test_pubspec_uses_build_number_without_abi_discriminator(self):
        self.assertEqual(pubspec_version("name: y300\nversion: 1.2.3+58\n"), ("1.2.3", 58))
        self.assertEqual(apk_name("1.2.3"), "y300-v1.2.3-android-arm64-v8a-release.apk")

    def test_invalid_or_ambiguous_versions_fail(self):
        for value in ["1.2.3", "1.2.3+0", "01.2.3+1", "1.2.3-beta+1", "1.2.3+2100000001",
                      "1.2.3+1\nversion: 1.2.4+2"]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                pubspec_version("version: " + value)

    def test_release_cannot_reuse_existing_version_or_code(self):
        release.validate_identity("v1.1.6", COMMIT, "1.1.6", 44, BASELINE)
        for tag, version, code in [("v1.1.6", "1.1.5", 44), ("v1.1.5", "1.1.5", 50),
                                   ("v1.1.6", "1.1.6", 43), ("v1.1.6", "1.1.6", 42)]:
            with self.subTest(tag=tag, code=code), self.assertRaises(ValueError):
                release.validate_identity(tag, COMMIT, version, code, BASELINE)

    def test_annotated_remote_tag_is_peeled_and_main_ancestry_checked(self):
        with patch.object(release, "run", side_effect=["", f"{'c' * 40}\trefs/tags/v1.1.6\n{COMMIT}\trefs/tags/v1.1.6^{{}}", COMMIT]):
            release.validate_remote_tag("v1.1.6", COMMIT)
        for remote, ancestor in [("c" * 40, COMMIT), (COMMIT, "c" * 40)]:
            with patch.object(release, "run", side_effect=["", f"{remote}\trefs/tags/v1.1.6", ancestor]):
                with self.assertRaises(ValueError):
                    release.validate_remote_tag("v1.1.6", COMMIT)


class ApkTests(unittest.TestCase):
    def metadata(self):
        return android.parse_metadata("package: name='com.adws.y300' versionCode='44' versionName='1.1.6'",
                                      f"Signer #1 certificate SHA-256 digest: {CERTIFICATE}",
                                      ["lib/arm64-v8a/libapp.so", "assets/a.txt"])

    def test_valid_distribution_apk(self):
        android.verify_metadata(self.metadata(), "1.1.6", 44, CERTIFICATE)

    def test_wrong_signer_package_version_code_or_abi_fails(self):
        for key, value in [("application_id", "com.example.y300"), ("version_name", "1.1.5"),
                           ("version_code", 1044), ("certificate_sha256", "c" * 64),
                           ("abis", ["arm64-v8a", "x86_64"]), ("abis", [])]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                android.verify_metadata({**self.metadata(), key: value}, "1.1.6", 44, CERTIFICATE)

    def test_ambiguous_signer_is_not_guessed(self):
        with self.assertRaises(ValueError):
            android.parse_metadata("package: name='com.adws.y300' versionCode='44' versionName='1.1.6'",
                                   f"Signer #1 certificate SHA-256 digest: {CERTIFICATE}\nSigner #2 certificate SHA-256 digest: {CERTIFICATE}", [])


class SigningTests(unittest.TestCase):
    def test_java_properties_preserve_special_characters(self):
        escaped = signing.property_value("空 😀\\=:\n pass")
        self.assertEqual(escaped, r"\u7a7a\u0020\ud83d\ude00\u005c\u003d\u003a\u000a\u0020pass")

    def test_missing_secret_cannot_create_material(self):
        with patch.dict(os.environ, {}, clear=True), self.assertRaises(ValueError):
            signing.restore()

    def test_restore_and_cleanup_stay_outside_checkout(self):
        with tempfile.TemporaryDirectory() as directory:
            environment = {"RUNNER_TEMP": directory, "GITHUB_ENV": str(Path(directory) / "env"),
                           "ANDROID_KEYSTORE_BASE64": base64.b64encode(b"fixture-key").decode(),
                           "ANDROID_KEYSTORE_PASSWORD": "fixture-pass", "ANDROID_KEY_ALIAS": "fixture-alias",
                           "ANDROID_KEY_PASSWORD": "fixture-pass"}
            with patch.dict(os.environ, environment):
                signing.restore()
                self.assertEqual((signing.signing_directory() / "release.jks").read_bytes(), b"fixture-key")
                self.assertNotIn("fixture-pass", Path(environment["GITHUB_ENV"]).read_text(encoding="utf-8"))
                signing.cleanup()
                self.assertFalse(signing.signing_directory().exists())

    def test_invalid_base64_is_cleaned_without_echoing_input(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.dict(os.environ, {"RUNNER_TEMP": directory, **{key: "private-invalid!" for key in signing.KEYS}}):
                with self.assertRaisesRegex(ValueError, "Could not restore") as error:
                    signing.restore()
                self.assertNotIn("private-invalid", str(error.exception))
                self.assertFalse(signing.signing_directory().exists())


class DraftTests(unittest.TestCase):
    def draft(self):
        return {"id": 1, "tag_name": "v1.1.6", "target_commitish": COMMIT, "draft": True,
                "prerelease": False, "body": github.identity_marker("v1.1.6", COMMIT, 44) + "\nMaintainer notes",
                "assets": [], "html_url": "https://github.com/example/repo/releases/tag/v1.1.6"}

    def test_only_same_unpublished_draft_can_be_reused(self):
        github.draft_identity(self.draft(), "v1.1.6", COMMIT, 44)
        for key, value in [("draft", False), ("prerelease", True), ("body", "manual draft"),
                           ("target_commitish", "main"), ("tag_name", "v1.1.7")]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                github.draft_identity({**self.draft(), key: value}, "v1.1.6", COMMIT, 44)

    def test_existing_prerelease_is_rejected_during_preflight(self):
        with self.assertRaises(ValueError):
            github.check_release_history([{**self.draft(), "prerelease": True}],
                                         "v1.1.6", COMMIT, 44, BASELINE)

    def test_corrupted_distribution_or_noncanonical_checksum_cannot_upload(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            name = apk_name("1.1.6")
            apk = path / name
            apk.write_bytes(b"fixture-apk")
            digest = android.sha256(apk)
            manifest = {"schema": 1, "apk": name, "version_name": "1.1.6",
                        "sha256": digest, "size": apk.stat().st_size}
            checksum = path / (name + ".sha256")
            canonical = f"{digest}  {name}\n".encode()
            checksum.write_bytes(canonical)
            release.verify_distribution(path, manifest)
            checksum.write_bytes(canonical.replace(b"  ", b" "))
            with self.assertRaises(ValueError):
                release.verify_distribution(path, manifest)
            checksum.write_bytes(canonical)
            apk.write_bytes(b"changed-apk")
            with self.assertRaises(ValueError):
                release.verify_distribution(path, manifest)

    def test_history_handles_legacy_baseline_and_rejects_unknown_new_release(self):
        legacy = {"tag_name": "v1.1.5", "prerelease": False, "draft": False, "assets": []}
        github.check_release_history([legacy], "v1.1.6", COMMIT, 44, BASELINE)
        with self.assertRaises(ValueError):
            github.check_release_history([{**legacy, "tag_name": "v1.1.6"}], "v1.1.7", COMMIT, 45, BASELINE)
        with self.assertRaises(ValueError):
            github.check_release_history([{**legacy, "tag_name": "v2.0.0"}], "v1.1.6", COMMIT, 44, BASELINE)

    def test_other_pending_drafts_reserve_their_build_number(self):
        github.check_release_history([self.draft()], "v1.1.7", COMMIT, 45, BASELINE)
        with self.assertRaises(ValueError):
            github.check_release_history([self.draft()], "v1.1.7", COMMIT, 44, BASELINE)

    def test_interrupted_upload_can_resume_without_rewriting_notes(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            manifest = {"tag": "v1.1.6", "commit": COMMIT, "version_code": 44, "apk": apk_name("1.1.6")}
            for name in [manifest["apk"], manifest["apk"] + ".sha256", "release-manifest.json"]:
                (path / name).write_text(name, encoding="utf-8")
            state = self.draft()
            original_body = state["body"]
            uploaded = {}
            fail = [True]

            def command(*args):
                self.assertEqual(args[:3], ("gh", "release", "upload"))
                file = Path(args[4])
                if file.name == "release-manifest.json" and fail[0]:
                    fail[0] = False
                    raise RuntimeError("connection lost")
                uploaded[file.name] = file.read_bytes()
                state["assets"] = [{"name": name, "id": i, "state": "uploaded"} for i, name in enumerate(uploaded)]
                return ""

            def download(args):
                asset_id = int(args[2].split("/")[-1])
                return uploaded[state["assets"][asset_id]["name"]]

            with patch.object(github, "releases", side_effect=lambda: [deepcopy(state)]), \
                 patch.object(github, "api", side_effect=lambda _: deepcopy(state)), \
                 patch.object(github, "run", side_effect=command), \
                 patch.object(github.subprocess, "check_output", side_effect=download), \
                 patch.dict(os.environ, {"GITHUB_REPOSITORY": "example/repo"}):
                with self.assertRaisesRegex(RuntimeError, "connection lost"):
                    github.publish_draft(path, manifest)
                self.assertNotIn("release-manifest.json", uploaded)
                self.assertEqual(github.publish_draft(path, manifest), state["html_url"])
            self.assertEqual(len(uploaded), 3)
            self.assertEqual(state["body"], original_body)


if __name__ == "__main__":
    unittest.main()
