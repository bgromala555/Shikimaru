"""SSE events endpoint -- streams job events to the Android client.

Uses ``sse-starlette`` to provide a standards-compliant Server-Sent Events
stream.  The Android app connects here after triggering an ask, plan, or
execute action and receives real-time log lines, step updates, completion
signals, and error messages.
"""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING

from fastapi import APIRouter, HTTPException, Query
from sse_starlette.sse import EventSourceResponse

from runner.models import JobStatusResponse

if TYPE_CHECKING:
    import asyncio
    from collections.abc import AsyncGenerator

    from runner.models import JobEvent
    from runner.services.job_manager import JobManager

logger = logging.getLogger(__name__)

router = APIRouter(tags=["events"])

_job_manager: JobManager | None = None


def set_job_manager(manager: JobManager) -> None:
    """Wire the shared ``JobManager`` into this router module.

    Args:
        manager: The application-wide ``JobManager`` instance.
    """
    global _job_manager
    _job_manager = manager


def _get_manager() -> JobManager:
    """Return the wired ``JobManager`` or raise if not initialised.

    Returns:
        The active ``JobManager``.

    Raises:
        HTTPException: If the manager has not been set yet.
    """
    if _job_manager is None:
        raise HTTPException(status_code=503, detail="JobManager not initialised")
    return _job_manager


async def _event_generator(job_id: str) -> AsyncGenerator[dict[str, str], None]:
    """Async generator that pulls events from the job queue and formats them for SSE.

    The generator runs until it encounters a ``done`` or ``error`` event, at
    which point it yields that final event and stops.

    Args:
        job_id: The job whose events should be streamed.

    Yields:
        Dicts with ``event`` and ``data`` keys suitable for
        ``EventSourceResponse``.
    """
    manager = _get_manager()
    queue: asyncio.Queue[JobEvent] = await manager.get_events(job_id)

    while True:
        event = await queue.get()
        yield {
            "event": event.event_type.value,
            "data": event.data,
        }
        # Terminal events end the stream
        if event.event_type.value in {"done", "error"}:
            break


@router.get("/events")
async def stream_events(
    job_id: str = Query(description="The job ID to stream events for"),
) -> EventSourceResponse:
    """Open an SSE stream for the specified job.

    The client receives events with types ``step``, ``log``, ``done``, and
    ``error``.  The stream closes automatically once a terminal event is
    emitted.

    Args:
        job_id: Identifier of the job to stream.

    Returns:
        An ``EventSourceResponse`` that yields server-sent events.

    Raises:
        HTTPException: If the job does not exist.
    """
    manager = _get_manager()
    try:
        manager.get_job(job_id)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=f"Job {job_id!r} not found") from exc

    return EventSourceResponse(_event_generator(job_id))


@router.get("/job-status", response_model=JobStatusResponse)
async def get_job_status(
    job_id: str = Query(description="The job ID to check status for"),
) -> JobStatusResponse:
    """Lightweight polling endpoint for job progress.

    The Android client polls this every few seconds during execution as a
    reliable alternative to SSE, which can be flaky over mobile Wi-Fi.

    Args:
        job_id: Identifier of the job to check.

    Returns:
        A ``JobStatusResponse`` with current state and latest event data.

    Raises:
        HTTPException: If the job does not exist.
    """
    manager = _get_manager()
    try:
        job = manager.get_job(job_id)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=f"Job {job_id!r} not found") from exc

    latest = job.events[-1].data if job.events else ""
    return JobStatusResponse(
        job_id=job.job_id,
        state=job.state.value,
        event_count=len(job.events),
        latest_event=latest,
    )
