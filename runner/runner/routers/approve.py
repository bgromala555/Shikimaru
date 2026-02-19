"""Approve endpoint -- transitions a plan from PLAN_READY to APPROVED.

This is the gating step: execution cannot proceed until the user has
explicitly approved the generated plan via this endpoint.
"""

import logging

from fastapi import APIRouter, HTTPException

from runner.models import ApproveRequest, ApproveResponse, JobState
from runner.services.job_manager import JobManager
from runner.state_machine import InvalidTransitionError

logger = logging.getLogger(__name__)

router = APIRouter(tags=["approve"])

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


@router.post("/approve", response_model=ApproveResponse)
async def approve_plan(request: ApproveRequest) -> ApproveResponse:
    """Approve a generated plan so that execution can proceed.

    Looks up the job by its ``plan_id`` and transitions it from PLAN_READY to
    APPROVED.  If the plan has not been generated yet, or the job is in an
    unexpected state, an appropriate HTTP error is returned.

    Args:
        request: Contains the ``plan_id`` to approve.

    Returns:
        An ``ApproveResponse`` confirming the approval.

    Raises:
        HTTPException: If the plan is not found or the state transition is
            illegal.
    """
    manager = _get_manager()

    try:
        job = manager.get_job_by_plan_id(request.plan_id)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=f"Plan {request.plan_id!r} not found") from exc

    try:
        manager.transition(job.job_id, JobState.APPROVED)
    except InvalidTransitionError as exc:
        raise HTTPException(
            status_code=409,
            detail=f"Cannot approve: job is in state {job.state.value!r}, expected 'plan_ready'",
        ) from exc

    logger.info("Plan %s approved for job %s", request.plan_id, job.job_id)
    return ApproveResponse(job_id=job.job_id, status="approved")
