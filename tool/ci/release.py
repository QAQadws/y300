"""Validate release identity, verify the signed APK and prepare a GitHub draft."""

import argparse
from datetime import datetime, timezone
import os
from pathlib import Path
import shutil

from android import inspect_apk, sha256, verify_metadata
from common import ROOT, TAG, apk_name, pubspec_version, read_json, require, run, summary, version_tuple, write_json
import github_release


def validate_identity(tag, commit, version, code, baseline):
    require(TAG.fullmatch(tag) is not None, "Expected stable vX.Y.Z tag")
    require(tag == "v" + version, "Tag and pubspec version disagree")
    require(len(commit) == 40 and all(char in "0123456789abcdef" for char in commit), "Invalid release commit")
    require(version_tuple(version) > version_tuple(baseline["version_name"]), "Version must exceed the published baseline")
    require(code > baseline["version_code"], "versionCode must exceed the actual published APK baseline")


def validate_remote_tag(tag, commit):
    run("git", "fetch", "--no-tags", "origin", "+refs/heads/main:refs/remotes/origin/main")
    remote = run("git", "ls-remote", "origin", f"refs/tags/{tag}", f"refs/tags/{tag}^{{}}")
    refs = dict(line.split()[::-1] for line in remote.splitlines())
    require(refs.get(f"refs/tags/{tag}^{{}}", refs.get(f"refs/tags/{tag}")) == commit, "Remote tag moved or does not identify this commit")
    require(run("git", "merge-base", commit, "origin/main") == commit, "Release commit is not contained in main")


def validate():
    ref = os.environ["GITHUB_REF"]
    require(ref.startswith("refs/tags/"), "Release requires a tag ref")
    tag = ref.removeprefix("refs/tags/")
    commit = os.environ["GITHUB_SHA"]
    require(run("git", "rev-parse", "HEAD") == commit, "Checkout changed since CI validation")
    version, code = pubspec_version()
    baseline = read_json(ROOT / "tool/ci/release-baseline.json")
    validate_identity(tag, commit, version, code, baseline)
    validate_remote_tag(tag, commit)
    github_release.check_release_history(github_release.releases(), tag, commit, code, baseline)
    return tag, commit, version, code, baseline


def package(directory):
    tag, commit, version, code, baseline = validate()
    name = apk_name(version)
    source = ROOT / "build/app/outputs/apk/release" / name
    metadata = inspect_apk(source)
    verify_metadata(metadata, version, code, baseline["certificate_sha256"])
    directory.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, directory / name)
    (directory / (name + ".sha256")).write_text(f"{metadata['sha256']}  {name}\n", encoding="utf-8")
    sdk = read_json(Path(os.environ["RUNNER_TEMP"]) / "flutter-version.json")
    require(sdk["frameworkVersion"] == (ROOT / ".flutter-version").read_text(encoding="utf-8").strip(),
            "Actual Flutter version differs from the repository pin")
    manifest = {"schema": 1, "tag": tag, "commit": commit, **metadata, "apk": name,
                "flutter_version": sdk["frameworkVersion"], "dart_version": sdk["dartSdkVersion"],
                "built_at": datetime.now(timezone.utc).isoformat(),
                "run_url": f"https://github.com/{github_release.repository()}/actions/runs/{os.environ['GITHUB_RUN_ID']}"}
    write_json(directory / "release-manifest.json", manifest)
    summary(f"Verified signed APK `{name}` for `{commit}`; SHA-256 `{metadata['sha256']}`.")


def verify_distribution(directory, manifest):
    name = apk_name(manifest["version_name"])
    require(manifest["schema"] == 1 and manifest["apk"] == name, "Invalid distribution manifest")
    apk = directory / name
    require(apk.stat().st_size == manifest["size"] and sha256(apk) == manifest["sha256"],
            "Prepared APK no longer matches the verified manifest")
    require((directory / (name + ".sha256")).read_bytes() ==
            f"{manifest['sha256']}  {name}\n".encode("utf-8"), "Checksum is not the canonical APK checksum")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["validate", "package", "draft"])
    parser.add_argument("--directory", type=Path, default=ROOT / "build/ci-release")
    args = parser.parse_args()
    if args.command == "package":
        package(args.directory)
    elif args.command == "draft":
        tag, commit, version, code, _ = validate()
        manifest = read_json(args.directory / "release-manifest.json")
        require((manifest["tag"], manifest["commit"], manifest["version_code"], manifest["apk"]) ==
                (tag, commit, code, apk_name(version)), "Prepared manifest identity mismatch")
        verify_distribution(args.directory, manifest)
        summary("Draft ready for manual review: " + github_release.publish_draft(args.directory, manifest))
    else:
        validate()
