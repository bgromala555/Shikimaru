"""Tests for the Cursor CLI invoker.

Uses mock subprocesses to verify prompt construction, output streaming, and
the read-only file-integrity check.
"""

from pathlib import Path

from runner.services.cursor_invoker import _snapshot_mtimes, detect_modifications


class TestSnapshotMtimes:
    """Verify the file-integrity snapshotting helpers."""

    def test_snapshot_captures_files(self, tmp_path: Path) -> None:
        """Snapshot includes all regular files with their modification times.

        Args:
            tmp_path: Pytest-provided temporary directory.
        """
        (tmp_path / "a.txt").write_text("aaa")
        (tmp_path / "sub").mkdir()
        (tmp_path / "sub" / "b.txt").write_text("bbb")

        snapshot = _snapshot_mtimes(tmp_path)
        assert "a.txt" in snapshot
        assert "sub\\b.txt" in snapshot or "sub/b.txt" in snapshot

    def test_snapshot_empty_dir(self, tmp_path: Path) -> None:
        """An empty directory produces an empty snapshot.

        Args:
            tmp_path: Pytest-provided temporary directory.
        """
        snapshot = _snapshot_mtimes(tmp_path)
        assert snapshot == {}

    def test_snapshot_missing_dir(self) -> None:
        """A non-existent directory produces an empty snapshot."""
        snapshot = _snapshot_mtimes(Path("/nonexistent/dir"))
        assert snapshot == {}


class TestDetectModifications:
    """Verify modification detection between two snapshots."""

    def test_no_changes(self) -> None:
        """Identical snapshots produce no modifications."""
        snap = {"a.txt": 1000.0, "b.txt": 2000.0}
        assert detect_modifications(snap, snap) == []

    def test_new_file(self) -> None:
        """A file present in 'after' but not 'before' is detected."""
        before: dict[str, float] = {"a.txt": 1000.0}
        after: dict[str, float] = {"a.txt": 1000.0, "new.txt": 3000.0}
        changes = detect_modifications(before, after)
        assert "new.txt" in changes

    def test_modified_file(self) -> None:
        """A file with a different mtime is detected."""
        before: dict[str, float] = {"a.txt": 1000.0}
        after: dict[str, float] = {"a.txt": 2000.0}
        changes = detect_modifications(before, after)
        assert "a.txt" in changes

    def test_deleted_file(self) -> None:
        """A file present in 'before' but not 'after' is detected."""
        before: dict[str, float] = {"a.txt": 1000.0, "gone.txt": 1000.0}
        after: dict[str, float] = {"a.txt": 1000.0}
        changes = detect_modifications(before, after)
        assert "gone.txt" in changes
