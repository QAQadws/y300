"""Restore ephemeral signing files without exposing credentials in arguments."""

import base64
import os
from pathlib import Path
import shutil
import sys

from common import require

KEYS = ("ANDROID_KEYSTORE_BASE64", "ANDROID_KEYSTORE_PASSWORD", "ANDROID_KEY_ALIAS", "ANDROID_KEY_PASSWORD")


def property_value(value):
    # java.util.Properties reads ISO-8859-1 and treats backslashes as escapes.
    result = []
    for char in value:
        if char in "\\:=#! " or char in "\r\n\t":
            result.append("\\u%04x" % ord(char))
        elif ord(char) > 127:
            encoded = char.encode("utf-16-be")
            result.extend("\\u" + encoded[i:i + 2].hex() for i in range(0, len(encoded), 2))
        else:
            result.append(char)
    return "".join(result)


def signing_directory():
    parent = Path(os.environ["RUNNER_TEMP"]).resolve()
    directory = parent / "y300-release-signing"
    require(directory.resolve().parent == parent and not directory.is_symlink(), "Unsafe signing directory")
    return directory


def restore():
    require(all(os.environ.get(key) for key in KEYS), "Required Android signing secrets are missing")
    directory = signing_directory()
    require(not directory.exists(), "Signing directory already exists")
    directory.mkdir(mode=0o700)
    try:
        key = base64.b64decode(os.environ[KEYS[0]], validate=True)
        require(key, "Empty keystore")
        key_path = directory / "release.jks"
        key_path.write_bytes(key)
        key_path.chmod(0o600)
        properties = {"storeFile": key_path.as_posix(), "storePassword": os.environ[KEYS[1]],
                      "keyAlias": os.environ[KEYS[2]], "keyPassword": os.environ[KEYS[3]]}
        config = directory / "key.properties"
        config.write_text("".join(f"{name}={property_value(value)}\n" for name, value in properties.items()), encoding="ascii")
        config.chmod(0o600)
        with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as stream:
            stream.write(f"ORG_GRADLE_PROJECT_y300SigningProperties={config.as_posix()}\n")
    except Exception:
        cleanup()
        raise ValueError("Could not restore Android signing material") from None


def cleanup():
    directory = signing_directory()
    if directory.exists():
        shutil.rmtree(directory)


if __name__ == "__main__":
    require(len(sys.argv) == 2 and sys.argv[1] in {"restore", "cleanup"}, "Expected restore or cleanup")
    {"restore": restore, "cleanup": cleanup}[sys.argv[1]]()
