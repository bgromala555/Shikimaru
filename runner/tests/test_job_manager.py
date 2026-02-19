"""Tests for the job manager service.

Covers job creation, state transitions, event recording, and artifact
persistence.
"""

from pathlib import Path

import pytest

from runner.models import EventType, JobState
from runner.services.job_manager import JobManager
from runner.state_machine import InvalidTransitionError


@pytest.fixture()
def manager(tmp_path: Path) -> JobManager:
    """Create a ``JobManager`` backed by a temporary artifacts directory.

    Args:
        tmp_path: Pytest-provided temporary directory.

    Returns:
        A fresh ``JobManager`` instance.
    """
    return JobManager(artifacts_root=tmp_path)


def test_create_job(manager: JobManager) -> None:
    """A newly created job is in DRAFT state with a unique ID.

    Args:
        manager: Fixture-provided ``JobManager``.
    """
    job = manager.create_job("/fake/path")
    assert job.state == JobState.DRAFT
    assert len(job.job_id) == 12
    assert job.project_path == "/fake/path"


def test_get_job(manager: JobManager) -> None:
    """Jobs can be retrieved by their ID after creation.

    Args:
        manager: Fixture-provided ``JobManager``.
    """
    job = manager.create_job("/fake/path")
    retrieved = manager.get_job(job.job_id)
    assert retrieved.job_id == job.job_id


def test_get_job_missing(manager: JobManager) -> None:
    """Requesting a non-existent job raises KeyError.

    Args:
        manager: Fixture-provided ``JobManager``.
    """
    with pytest.raises(KeyError):
        manager.get_job("nonexistent")


def test_transition(manager: JobManager) -> None:
    """Legal transitions update the job state.

    Args:
        manager: Fixture-provided ``JobManager``.
    """
    job = manager.create_job("/fake/path")
    updated = manager.transition(job.job_id, JobState.ASK_RUNNING)
    assert updated.state == JobState.ASK_RUNNING


def test_invalid_transition(manager: JobManager) -> None:
    """Illegal transitions raise ``InvalidTransitionError``.

    Args:
        manager: Fixture-provided ``JobManager``.
    """
    job = manager.create_job("/fake/path")
    with pytest.raises(InvalidTransitionError):
        manager.transition(job.job_id, JobState.EXECUTING)


@pytest.mark.asyncio()
async def test_add_and_get_events(manager: JobManager) -> None:
    """Events are recorded on the job and available via the queue.

    Args:
        manager: Fixture-provided ``JobManager``.
    """
    job = manager.create_job("/fake/path")
    await manager.add_event(job.job_id, EventType.LOG, "hello world")

    queue = await manager.get_events(job.job_id)
    event = queue.get_nowait()
    assert event.event_type == EventType.LOG
    assert event.data == "hello world"


def test_save_artifact(manager: JobManager) -> None:
    """Artifacts are written to the correct path on disk.

    Args:
        manager: Fixture-provided ``JobManager``.
    """
    job = manager.create_job("/fake/path")
    path = manager.save_artifact(job.job_id, "plan.md", "# My Plan")
    assert path.exists()
    assert path.read_text(encoding="utf-8") == "# My Plan"


def test_save_run_metadata(manager: JobManager) -> None:
    """``run.json`` is persisted with valid JSON content.

    Args:
        manager: Fixture-provided ``JobManager``.
    """
    job = manager.create_job("/fake/path")
    path = manager.save_run_metadata(job.job_id)
    assert path.exists()
    assert path.name == "run.json"


def test_get_job_by_plan_id(manager: JobManager) -> None:
    """Jobs can be looked up by their associated plan_id.

    Args:
        manager: Fixture-provided ``JobManager``.
    """
    job = manager.create_job("/fake/path")
    job.plan_id = "test-plan-123"
    retrieved = manager.get_job_by_plan_id("test-plan-123")
    assert retrieved.job_id == job.job_id


def test_get_job_by_plan_id_missing(manager: JobManager) -> None:
    """Looking up a non-existent plan_id raises KeyError.

    Args:
        manager: Fixture-provided ``JobManager``.
    """
    with pytest.raises(KeyError):
        manager.get_job_by_plan_id("nonexistent")
