"""GitHub release I/O and conservative recovery for unpublished drafts."""

import json
import os
from pathlib import Path
import re
import subprocess

from common import TAG, require, run, version_tuple

MARKER = re.compile(r"<!-- y300-release:(\{[^\n]*\}) -->")


def repository():
    value = os.environ["GITHUB_REPOSITORY"]
    require(re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", value), "Invalid GitHub repository")
    return value


def api(path):
    return json.loads(run("gh", "api", f"repos/{repository()}/{path}"))


def releases():
    pages = json.loads(run("gh", "api", "--paginate", "--slurp", f"repos/{repository()}/releases?per_page=100"))
    return [release for page in pages for release in page]


def identity_marker(tag, commit, code):
    return "<!-- y300-release:" + json.dumps({"tag": tag, "commit": commit, "version_code": code}, separators=(",", ":")) + " -->"


def draft_identity(release, tag, commit, code):
    require(release.get("draft") is True, "Published releases cannot be overwritten")
    require(release.get("prerelease") is False, "Prerelease cannot be reused as a stable draft")
    require(release.get("tag_name") == tag, "Draft tag mismatch")
    markers = MARKER.findall(release.get("body") or "")
    require(len(markers) == 1, "Draft has no unique workflow identity; inspect it manually")
    require(json.loads(markers[0]) == {"tag": tag, "commit": commit, "version_code": code}, "Draft identity mismatch")
    require(release.get("target_commitish") == commit, "Draft target commit mismatch")


def check_release_history(history, tag, commit, code, baseline):
    for release in history:
        name = release.get("tag_name", "")
        if not TAG.fullmatch(name) or release.get("prerelease"):
            continue
        if name == tag:
            draft_identity(release, tag, commit, code)
            continue
        require(version_tuple(tag[1:]) > version_tuple(name[1:]), "Version must exceed existing stable releases and drafts")
        if version_tuple(name[1:]) <= version_tuple(baseline["version_name"]):
            continue
        manifests = [asset for asset in release["assets"] if asset["name"] == "release-manifest.json"]
        if not manifests and release.get("draft"):
            markers = MARKER.findall(release.get("body") or "")
            require(len(markers) == 1, "Other draft is missing release identity")
            previous = json.loads(markers[0])
        else:
            require(len(manifests) == 1, "Release after the baseline has no unique manifest")
            previous = json.loads(run("gh", "api", f"repos/{repository()}/releases/assets/{manifests[0]['id']}", "-H", "Accept: application/octet-stream"))
            require(previous["tag"] == name, "Published manifest tag mismatch")
        require(isinstance(previous.get("version_code"), int) and code > previous["version_code"], "versionCode must exceed release history")


def publish_draft(directory, manifest):
    tag, commit, code = manifest["tag"], manifest["commit"], manifest["version_code"]
    existing = [item for item in releases() if item["tag_name"] == tag]
    require(len(existing) <= 1, "Ambiguous release identity")
    if existing:
        draft_identity(existing[0], tag, commit, code)
    else:
        notes = Path(directory) / "notes.md"
        notes.write_text(identity_marker(tag, commit, code) + "\n\nReview release notes and the APK before publishing.\n", encoding="utf-8")
        run("gh", "release", "create", tag, "--repo", repository(), "--verify-tag", "--target", commit,
            "--draft", "--title", tag, "--notes-file", str(notes))
    # Upload the manifest last. Reruns may replace only assets of this exact draft.
    files = [manifest["apk"], manifest["apk"] + ".sha256", "release-manifest.json"]
    for name in files:
        current = api(f"releases/tags/{tag}")
        draft_identity(current, tag, commit, code)
        run("gh", "release", "upload", tag, str(Path(directory) / name), "--repo", repository(), "--clobber")
    current = api(f"releases/tags/{tag}")
    draft_identity(current, tag, commit, code)
    for name in files:
        assets = [asset for asset in current["assets"] if asset["name"] == name]
        require(len(assets) == 1 and assets[0]["state"] == "uploaded", f"Missing release asset: {name}")
        data = subprocess.check_output(["gh", "api", f"repos/{repository()}/releases/assets/{assets[0]['id']}", "-H", "Accept: application/octet-stream"])
        require(data == (Path(directory) / name).read_bytes(), f"Uploaded asset verification failed: {name}")
    return current["html_url"]
