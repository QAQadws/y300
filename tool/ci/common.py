"""Small, dependency-free primitives shared by CI checks and release tooling."""

import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
SEMVER = r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
TAG = re.compile(rf"v{SEMVER}\Z")
APPLICATION_ID = "com.adws.y300"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def run(*args, cwd=ROOT):
    return subprocess.check_output(args, cwd=cwd, text=True, encoding="utf-8").strip()


def read_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def write_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def version_tuple(name):
    require(re.fullmatch(SEMVER, name) is not None, "Invalid stable version name")
    return tuple(map(int, name.split(".")))


def pubspec_version(source=None):
    if source is None:
        source = (ROOT / "pubspec.yaml").read_text(encoding="utf-8")
    matches = re.findall(r"^version:\s*([^\s#]+)\s*(?:#.*)?$", source, re.MULTILINE)
    require(len(matches) == 1, "Expected exactly one pubspec version")
    match = re.fullmatch(rf"({SEMVER})\+([1-9][0-9]*)", matches[0])
    require(match is not None, "Expected X.Y.Z+positiveBuildNumber")
    name, code = match[1], int(match[5])
    require(code <= 2100000000, "versionCode exceeds the Android limit")
    return name, code


def apk_name(version):
    version_tuple(version)
    return f"y300-v{version}-android-arm64-v8a-release.apk"


def output(name, value):
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as stream:
            stream.write(f"{name}={value}\n")


def summary(message):
    print(message)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as stream:
            stream.write(message + "\n")
