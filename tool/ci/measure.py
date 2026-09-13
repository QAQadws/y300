"""Keep command output and failure semantics while reporting duration."""

import shutil
import subprocess
import sys
import time

from common import summary

if __name__ == "__main__":
    label, command, *arguments = sys.argv[1:]
    started = time.monotonic()
    result = subprocess.run([shutil.which(command) or command, *arguments], check=False)
    summary(f"{label}: exit `{result.returncode}`, elapsed `{time.monotonic() - started:.1f}s`.")
    sys.exit(result.returncode)
