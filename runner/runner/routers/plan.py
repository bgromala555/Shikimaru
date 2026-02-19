"""Plan endpoint -- generate a Markdown plan via Cursor agent (read-only).

This endpoint transitions an existing job (or creates a new one) to
PLAN_RUNNING, invokes the Cursor CLI in plan mode, and returns the generated
Markdown plan.
"""

import logging
import uuid

from fastapi import APIRouter, HTTPException

from runner.config import RunnerSettings
from runner.models import EventType, JobState, PlanRequest, PlanResponse
from runner.services.cursor_invoker import invoke_cursor
from runner.services.job_manager import JobManager
from runner.services.prompt_templates import build_plan_prompt

logger = logging.getLogger(__name__)

router = APIRouter(tags=["plan"])

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


@router.post("/plan", response_model=PlanResponse)
async def create_plan(request: PlanRequest) -> PlanResponse:
    """Generate a Markdown plan via the Cursor agent in read-only plan mode.

    If a ``session_id`` is provided, the agent resumes that session so it
    has full context from prior Ask exchanges.

    Args:
        request: The plan request with objective, constraints, and answers.

    Returns:
        A ``PlanResponse`` containing the plan ID, rendered Markdown, and
        session ID for continuity.

    Raises:
        HTTPException: On invocation failure.
    """
    manager = _get_manager()
    settings = RunnerSettings()

    job = manager.create_job(request.project_path)
    if request.session_id:
        job.session_id = request.session_id
    manager.transition(job.job_id, JobState.PLAN_RUNNING)

    prompt = build_plan_prompt(
        objective=request.objective,
        project_path=request.project_path,
        constraints=request.constraints or None,
        answers=request.answers or None,
        history=request.history or None,
    )

    try:
        result = await invoke_cursor(
            prompt=prompt,
            project_path=request.project_path,
            timeout_seconds=settings.cursor_timeout_seconds,
            mode="plan",
            session_id=request.session_id,
        )
    except TimeoutError as exc:
        manager.transition(job.job_id, JobState.FAILED)
        await manager.add_event(job.job_id, EventType.ERROR, "Cursor agent timed out")
        raise HTTPException(status_code=504, detail="Cursor agent timed out") from exc

    plan_markdown = result.text
    plan_id = uuid.uuid4().hex[:12]

    job.session_id = result.session_id
    job.plan_id = plan_id
    job.plan_markdown = plan_markdown
    manager.transition(job.job_id, JobState.PLAN_READY)
    await manager.add_event(job.job_id, EventType.DONE, "Plan generation completed")
    manager.save_artifact(job.job_id, "plan.md", plan_markdown)

    return PlanResponse(
        job_id=job.job_id,
        plan_id=plan_id,
        plan_markdown=plan_markdown,
        session_id=result.session_id,
    )
