"""Application configuration backed by Pydantic Settings.

All values can be overridden via environment variables prefixed with ``RUNNER_``
(e.g. ``RUNNER_PORT=9000``) or via a ``.env`` file in the runner working directory.
"""

from pathlib import Path

from pydantic_settings import BaseSettings


def _default_project_root() -> Path:
    """Return the default project root: ``~/Downloads/_projects``.

    The directory is *not* created automatically -- the project-discovery service
    handles that when it first scans.

    Returns:
        Resolved absolute path to the default project root.
    """
    return Path.home() / "Downloads" / "_projects"


def _default_artifacts_dir() -> Path:
    """Return the default artifacts directory: ``~/.orchestrator/jobs``.

    Each job stores its plan, summary, diff, and logs under a sub-directory
    named by the job ID.

    Returns:
        Resolved absolute path to the artifacts root.
    """
    return Path.home() / ".orchestrator" / "jobs"


class RunnerSettings(BaseSettings):
    """Central configuration for the Shikigami runner service.

    Values are loaded from environment variables (``RUNNER_`` prefix), a
    ``.env`` file, or fall back to sensible defaults.

    Attributes:
        project_root: Directory the runner scans for candidate projects.
        host: Network interface to bind the HTTP server to.
        port: TCP port for the HTTP server.
        artifacts_dir: Root directory for persisted job artifacts.
        run_tests_after_execute: Whether to run tests/lint automatically after execution.
        project_scan_days: Only surface projects modified within this many days.
        cursor_timeout_seconds: Maximum wall-clock seconds to wait for a single Cursor invocation.
    """

    model_config = {"env_prefix": "RUNNER_"}

    project_root: Path = _default_project_root()
    host: str = "0.0.0.0"
    port: int = 8423
    artifacts_dir: Path = _default_artifacts_dir()
    run_tests_after_execute: bool = True
    project_scan_days: int = 10
    cursor_timeout_seconds: int = 180
