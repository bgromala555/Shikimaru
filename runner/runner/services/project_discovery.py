"""Project discovery service -- scans the configured root for candidate project folders.

This module provides a single entry-point, ``scan_projects``, which walks the
top-level children of the project root directory and returns metadata for any
that qualify as projects (i.e. are directories modified within the look-back
window).
"""

import logging
from datetime import UTC, datetime, timedelta
from pathlib import Path

from runner.models import ProjectInfo

logger = logging.getLogger(__name__)


def _count_files(directory: Path) -> int:
    """Count the number of immediate (non-recursive) files in *directory*.

    Symbolic links and hidden items are included in the count.  Sub-directories
    are **not** counted.

    Args:
        directory: The folder to inspect.

    Returns:
        Number of files directly inside *directory*.
    """
    try:
        return sum(1 for child in directory.iterdir() if child.is_file())
    except PermissionError:
        logger.warning("Permission denied counting files in %s", directory)
        return 0


def scan_projects(project_root: Path, max_age_days: int = 10) -> list[ProjectInfo]:
    """Scan *project_root* for candidate project folders.

    Only top-level sub-directories whose last-modified timestamp falls within
    the *max_age_days* window are returned.  If the root directory does not
    exist it is created automatically and an empty list is returned.

    Args:
        project_root: Absolute path to the directory to scan.
        max_age_days: Maximum age in days -- folders modified longer ago than
            this are excluded from the results.

    Returns:
        A list of ``ProjectInfo`` records sorted by ``last_modified``
        descending (most recent first).
    """
    if not project_root.exists():
        logger.info("Project root %s does not exist -- creating it", project_root)
        project_root.mkdir(parents=True, exist_ok=True)
        return []

    cutoff = datetime.now(tz=UTC) - timedelta(days=max_age_days)
    projects: list[ProjectInfo] = []

    for child in project_root.iterdir():
        if not child.is_dir():
            continue

        mtime = datetime.fromtimestamp(child.stat().st_mtime, tz=UTC)
        if mtime < cutoff:
            continue

        projects.append(
            ProjectInfo(
                name=child.name,
                path=str(child.resolve()),
                last_modified=mtime,
                file_count=_count_files(child),
            )
        )

    # Most recently modified first
    projects.sort(key=lambda p: p.last_modified, reverse=True)
    return projects
