"""Cheap structural test: every terraform/<NN>-* folder has the same set of root files."""
from pathlib import Path

REQUIRED = {"backend.tf", "providers.tf", "variables.tf", "versions.tf", "README.md"}


def test_every_folder_has_required_files():
    for d in sorted(Path("terraform").iterdir()):
        if not d.is_dir():
            continue
        files = {f.name for f in d.iterdir() if f.is_file()}
        missing = REQUIRED - files
        assert not missing, f"{d.name} missing: {missing}"


def test_every_folder_has_at_least_one_resource():
    for d in sorted(Path("terraform").iterdir()):
        if not d.is_dir():
            continue
        # README + boilerplate doesn't count; we want a real .tf besides those
        non_boilerplate = [
            f for f in d.glob("*.tf")
            if f.name not in {"backend.tf", "providers.tf", "variables.tf", "versions.tf"}
        ]
        assert non_boilerplate, f"{d.name} has no resource .tf files"
