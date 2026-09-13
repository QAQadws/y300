"""CI context, changed-file formatting, generated-file and aggregate gates."""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess

from common import ROOT, TAG, output, pubspec_version, read_json, require, run, summary


def release_requested(event_name, ref, mode):
    require(event_name in {"pull_request", "push", "workflow_dispatch"}, "Unsupported CI event")
    if event_name == "workflow_dispatch":
        require(mode in {"check", "release"}, "Invalid manual mode")
        if mode == "release":
            require(ref.startswith("refs/tags/"), "Manual release requires --ref vX.Y.Z")
            require(TAG.fullmatch(ref.removeprefix("refs/tags/")), "Invalid release tag")
            return True
        return False
    if event_name == "push" and ref.startswith("refs/tags/"):
        require(TAG.fullmatch(ref.removeprefix("refs/tags/")), "Invalid release tag")
        return True
    return False


def context():
    event = read_json(os.environ["GITHUB_EVENT_PATH"])
    release = release_requested(os.environ["GITHUB_EVENT_NAME"], os.environ["GITHUB_REF"],
                                event.get("inputs", {}).get("mode", "check"))
    require(run("git", "rev-parse", "HEAD") == os.environ["GITHUB_SHA"], "Checkout SHA mismatch")
    name, _ = pubspec_version()
    output("release", str(release).lower())
    output("version", name)
    summary(f"Validated commit `{os.environ['GITHUB_SHA']}`; release: `{release}`.")


def format_base(event_name, event, head):
    if event_name == "pull_request":
        return run("git", "merge-base", event["pull_request"]["base"]["sha"], head)
    before = event.get("before", "")
    if event_name == "push" and not os.environ.get("GITHUB_REF", "").startswith("refs/tags/"):
        if before and set(before) != {"0"}:
            return before
    # Manual/tag checks cover changes since the previous reachable stable tag.
    tags = [tag for tag in run("git", "tag", "--merged", head).splitlines() if TAG.fullmatch(tag)]
    tags = [tag for tag in tags if run("git", "rev-list", "-n", "1", tag) != head]
    if tags:
        return max(tags, key=lambda tag: tuple(map(int, tag[1:].split("."))))
    return subprocess.check_output(["git", "hash-object", "-t", "tree", "--stdin"],
                                   input=b"", cwd=ROOT).decode("ascii").strip()


def changed_dart_files(base, head="HEAD", cwd=ROOT):
    data = subprocess.check_output(["git", "diff", "--name-only", "--diff-filter=ACMR", "-z", base, head], cwd=cwd)
    return [name for name in data.decode("utf-8").split("\0")
            if name.endswith(".dart") and (Path(cwd) / name).is_file()]


def check_format():
    event = read_json(os.environ["GITHUB_EVENT_PATH"])
    files = changed_dart_files(format_base(os.environ["GITHUB_EVENT_NAME"], event, "HEAD"))
    for start in range(0, len(files), 60):
        subprocess.run([shutil.which("dart"), "format", "--output=none", "--set-exit-if-changed",
                        *files[start:start + 60]], cwd=ROOT, check=True)
    summary(f"Formatting checked: {len(files)} changed Dart files.")


def clean():
    require(not run("git", "diff", "--name-only", "HEAD"), "CI changed tracked files; regenerate locally and commit")
    require(not run("git", "ls-files", "--others", "--exclude-standard"), "CI generated untracked source files")
    untranslated = read_json(ROOT / "l10n_untranslated.json")
    require(isinstance(untranslated, dict) and not any(untranslated.values()), "Untranslated localization messages")


def gate(results):
    expected = {"quality", "package-tests", "app-tests", "android-check"}
    require(set(results) == expected, "Missing or unexpected required CI jobs")
    for name, job in results.items():
        require(job.get("result") == "success", f"Required job {name} did not succeed: {job.get('result')}")
    summary("All required analysis, tests and Android build checks passed.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["context", "format", "clean", "gate"])
    command = parser.parse_args().command
    if command == "gate":
        gate(json.loads(os.environ["CI_JOB_RESULTS"]))
    else:
        {"context": context, "format": check_format, "clean": clean}[command]()
