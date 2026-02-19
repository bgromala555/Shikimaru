"""Execute endpoint -- apply the approved plan via Cursor agent.

This endpoint transitions the job from APPROVED to EXECUTING, invokes the
Cursor agent in streaming mode with ``--resume`` to retain the full conversation
context, and pushes real-time progress events via SSE.

No hard timeout is applied to execution -- the agent runs until it finishes
(or the client disconnects and the runner is manually stopped).
"""

import json
import logging

from fastapi import APIRouter, BackgroundTasks, HTTPException

from runner.models import EventType, ExecuteRequest, ExecuteResponse, JobState
from runner.services.cursor_invoker import invoke_cursor_streaming
from runner.services.job_manager import JobManager
from runner.services.prompt_templates import build_execute_prompt
from runner.state_machine import InvalidTransitionError

logger = logging.getLogger(__name__)

router = APIRouter(tags=["execute"])

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


async def _run_execution(job_id: str, plan_markdown: str, project_path: str, session_id: str) -> None:
    """Background task that streams the Cursor agent output and records events.

    Uses ``invoke_cursor_streaming`` with ``--resume`` so the agent has full
    context of the ask and plan phases.  Each progress chunk is pushed to the
    job's SSE queue so the Android client can display real-time updates.

    No timeout is applied -- execution can take as long as it needs.

    Args:
        job_id: The job being executed.
        plan_markdown: Full Markdown text of the approved plan.
        project_path: Absolute path to the target project folder.
        session_id: Agent session ID for conversation continuity.
    """
    manager = _get_manager()

    prompt = build_execute_prompt(plan_markdown=plan_markdown, project_path=project_path)

    accumulated_text: list[str] = []

    try:
        await manager.add_event(job_id, EventType.STEP, "Starting Cursor agent in execute mode (streaming)")

        async for chunk in invoke_cursor_streaming(
            prompt=prompt,
            project_path=project_path,
            session_id=session_id,
        ):
            if chunk.startswith("__result__::"):
                raw_json = chunk[len("__result__::") :]
                try:
                    result_data = json.loads(raw_json)
                    final_text = result_data.get("result", "")
                    if final_text:
                        accumulated_text.append(final_text)
                except json.JSONDecodeError:
                    pass
                continue

            accumulated_text.append(chunk)
            await manager.add_event(job_id, EventType.LOG, chunk)

        full_output = "".join(accumulated_text)
        manager.save_artifact(job_id, "logs.txt", full_output)
        manager.save_artifact(job_id, "job_summary.md", full_output)

        manager.transition(job_id, JobState.COMPLETE)
        await manager.add_event(job_id, EventType.DONE, "Execution completed successfully")

    except Exception as exc:
        logger.exception("Execution failed for job %s", job_id)
        manager.transition(job_id, JobState.FAILED)
        await manager.add_event(job_id, EventType.ERROR, str(exc))

    finally:
        manager.save_run_metadata(job_id)


@router.post("/execute", response_model=ExecuteResponse)
async def execute_plan(request: ExecuteRequest, background_tasks: BackgroundTasks) -> ExecuteResponse:
    """Begin executing the approved plan.

    Looks up the job by ``plan_id``, transitions it from APPROVED to EXECUTING,
    and kicks off the Cursor agent invocation as a background task.  The agent
    resumes the same session used during ask/plan phases so it has full memory.

    Real-time progress is streamed via SSE -- connect to ``/events?job_id=...``
    to see live agent output.

    Args:
        request: Contains the ``plan_id`` to execute.
        background_tasks: FastAPI background task runner.

    Returns:
        An ``ExecuteResponse`` with the ``job_id`` for event streaming.

    Raises:
        HTTPException: If the plan is not found or not in an approvable state.
    """
    manager = _get_manager()

    try:
        job = manager.get_job_by_plan_id(request.plan_id)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=f"Plan {request.plan_id!r} not found") from exc

    try:
        manager.transition(job.job_id, JobState.EXECUTING)
    except InvalidTransitionError as exc:
        raise HTTPException(
            status_code=409,
            detail=f"Cannot execute: job is in state {job.state.value!r}, expected 'approved'",
        ) from exc

    background_tasks.add_task(
        _run_execution,
        job.job_id,
        job.plan_markdown,
        job.project_path,
        job.session_id,
    )
    logger.info("Execution started for job %s (plan %s, session %s)", job.job_id, request.plan_id, job.session_id[:12])

    return ExecuteResponse(job_id=job.job_id)
