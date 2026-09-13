"""Read and verify actual APK metadata with Android SDK tools."""

import argparse
import hashlib
import os
from pathlib import Path
import re
import zipfile

from common import APPLICATION_ID, require, run, write_json


def sha256(path):
    with open(path, "rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def build_tool(name):
    sdk = Path(os.environ.get("ANDROID_SDK_ROOT") or os.environ["ANDROID_HOME"])
    directories = [path for path in (sdk / "build-tools").iterdir()
                   if re.fullmatch(r"\d+\.\d+\.\d+", path.name)]
    require(directories, "Android SDK build-tools are missing")
    directory = max(directories, key=lambda path: tuple(map(int, path.name.split("."))))
    suffix = ".bat" if name == "apksigner" else ".exe"
    return str(directory / (name + suffix if os.name == "nt" else name))


def parse_metadata(badging, certificates, members):
    package = re.search(r"^package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'", badging, re.MULTILINE)
    require(package is not None, "APK package metadata is missing")
    certs = re.findall(r"^Signer #\d+ certificate SHA-256 digest: ([0-9a-fA-F]{64})$", certificates, re.MULTILINE)
    require(len(certs) == 1, "Expected one verified APK signer")
    abis = sorted({name.split("/")[1] for name in members if name.startswith("lib/") and name.endswith(".so")})
    return {"application_id": package[1], "version_code": int(package[2]),
            "version_name": package[3], "certificate_sha256": certs[0].lower(), "abis": abis}


def inspect_apk(path):
    # apksigner returning nonzero aborts before any digest is trusted.
    certificates = run(build_tool("apksigner"), "verify", "--verbose", "--print-certs", str(path))
    badging = run(build_tool("aapt"), "dump", "badging", str(path))
    with zipfile.ZipFile(path) as archive:
        metadata = parse_metadata(badging, certificates, archive.namelist())
    metadata["sha256"] = sha256(path)
    metadata["size"] = Path(path).stat().st_size
    return metadata


def verify_metadata(metadata, version, code, certificate=None):
    require(metadata["application_id"] == APPLICATION_ID, "APK application ID mismatch")
    require(metadata["version_name"] == version, "APK version name mismatch")
    require(metadata["version_code"] == code, "APK version code mismatch")
    require(metadata["abis"] == ["arm64-v8a"], "APK must contain only arm64-v8a native libraries")
    if certificate is not None:
        require(metadata["certificate_sha256"] == certificate, "APK signing certificate mismatch")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("apk", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    write_json(args.output, inspect_apk(args.apk.resolve()))
