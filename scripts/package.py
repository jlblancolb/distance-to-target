"""Build a reproducible, installable addon ZIP from an explicit file list."""

import re
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

ROOT = Path(__file__).resolve().parent.parent
FILES = (
    "DistanceToTarget.toc", "Estimator.lua", "Checks.lua", "DistanceToTarget.lua", "Options.lua", "README.md", "CHANGELOG.md",
    "LICENSE", "libs/LibStub/LibStub.lua", "libs/CallbackHandler-1.0/CallbackHandler-1.0.lua",
    "libs/LibRangeCheck-3.0/LibRangeCheck-3.0.lua", "libs/LibRangeCheck-3.0/LICENSE",
)


def package():
    toc = (ROOT / "DistanceToTarget.toc").read_text()
    match = re.search(r"^## Version: ([0-9A-Za-z.-]+)$", toc, re.MULTILINE)
    if not match:
        raise ValueError("Missing or invalid version in DistanceToTarget.toc")

    destination = ROOT / "dist" / f"DistanceToTarget-{match[1]}.zip"
    destination.parent.mkdir(exist_ok=True)
    with ZipFile(destination, "w", compression=ZIP_DEFLATED) as archive:
        for name in FILES:
            entry = ZipInfo(f"DistanceToTarget/{name}", date_time=(1980, 1, 1, 0, 0, 0))
            entry.compress_type = ZIP_DEFLATED
            entry.create_system = 3
            entry.external_attr = 0o100644 << 16
            archive.writestr(entry, (ROOT / name).read_bytes())

    with ZipFile(destination) as archive:
        assert archive.testzip() is None, "ZIP integrity check failed"
        assert archive.namelist() == [f"DistanceToTarget/{name}" for name in FILES]
    print(destination)


if __name__ == "__main__":
    package()
