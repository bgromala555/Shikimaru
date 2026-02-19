"""Tests for the project discovery service.

Uses temporary directories to simulate a project root with various folder
ages and verifies that the scanner filters and sorts correctly.
"""

import time
from pathlib import Path

import pytest

from runner.services.project_discovery import scan_projects


@pytest.fixture()
def project_root(tmp_path: Path) -> Path:
    """Create a temporary project root with three sub-directories.

    - ``recent_project``: modified just now
    - ``old_project``: modified 30 days ago
    - ``a_file.txt``: a regular file (should be ignored)

    Args:
        tmp_path: Pytest-provided temporary directory.

    Returns:
        Path to the temporary project root.
    """
    recent = tmp_path / "recent_project"
    recent.mkdir()
    (recent / "main.py").write_text("print('hello')")
    (recent / "README.md").write_text("# Recent")

    old = tmp_path / "old_project"
    old.mkdir()
    (old / "main.py").write_text("print('old')")
    # Set mtime to 30 days ago
    old_time = time.time() - (30 * 86400)
    import os

    os.utime(old, (old_time, old_time))

    # A plain file at root level -- should be ignored
    (tmp_path / "a_file.txt").write_text("not a project")

    return tmp_path


def test_scan_returns_recent_projects(project_root: Path) -> None:
    """Only projects modified within the look-back window are returned.

    Args:
        project_root: Fixture-provided temporary project root.
    """
    results = scan_projects(project_root, max_age_days=10)
    names = [p.name for p in results]
    assert "recent_project" in names
    assert "old_project" not in names


def test_scan_counts_files(project_root: Path) -> None:
    """The file_count field reflects the number of immediate files.

    Args:
        project_root: Fixture-provided temporary project root.
    """
    results = scan_projects(project_root, max_age_days=10)
    recent = next(p for p in results if p.name == "recent_project")
    assert recent.file_count == 2


def test_scan_sorted_by_most_recent(project_root: Path) -> None:
    """Results are ordered by last_modified descending.

    Args:
        project_root: Fixture-provided temporary project root.
    """
    # Widen the window so both show up
    results = scan_projects(project_root, max_age_days=365)
    assert len(results) == 2
    assert results[0].name == "recent_project"
    assert results[1].name == "old_project"


def test_scan_creates_missing_root(tmp_path: Path) -> None:
    """If the project root does not exist it is created and an empty list is returned.

    Args:
        tmp_path: Pytest-provided temporary directory.
    """
    missing_root = tmp_path / "nonexistent"
    results = scan_projects(missing_root, max_age_days=10)
    assert results == []
    assert missing_root.exists()
