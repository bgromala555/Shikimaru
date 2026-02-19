"""Ask endpoint -- read-only question/clarification via Cursor agent.

This endpoint creates a new job, transitions it to ASK_RUNNING, invokes the
Cursor CLI in ask mode (read-only), collects the response, and returns it.
The response may include clarification questions for the user.
"""

import logging

from fastapi import APIRouter, HTTPException

from runner.config import RunnerSettings
from runner.models import AskRequest, AskResponse, EventType, JobState
from runner.services.cursor_invoker import invoke_cursor
from runner.services.job_manager import JobManager
from runner.services.prompt_templates import build_ask_prompt

logger = logging.getLogger(__name__)

router = APIRouter(tags=["ask"])

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


@router.post("/ask", response_model=AskResponse)
async def ask(request: AskRequest) -> AskResponse:
    """Send a read-only question to the Cursor agent and return its answer.

    If a ``session_id`` is provided, the agent resumes that session so it
    retains memory of prior exchanges.  The returned ``session_id`` should
    be passed back on subsequent calls.

    Args:
        request: The ask request containing the project path and user message.

    Returns:
        An ``AskResponse`` with the agent's text, session ID, and any
        clarification questions.

    Raises:
        HTTPException: On invocation failure.
    """
    manager = _get_manager()
    settings = RunnerSettings()

    job = manager.create_job(request.project_path)
    if request.session_id:
        job.session_id = request.session_id
    manager.transition(job.job_id, JobState.ASK_RUNNING)

    prompt = build_ask_prompt(
        user_message=request.message,
        project_path=request.project_path,
        recent_days=request.context.recent_days,
        history=request.history or None,
    )

    try:
        result = await invoke_cursor(
            prompt=prompt,
            project_path=request.project_path,
            timeout_seconds=settings.cursor_timeout_seconds,
            mode="ask",
            session_id=request.session_id,
        )
    except TimeoutError as exc:
        manager.transition(job.job_id, JobState.FAILED)
        await manager.add_event(job.job_id, EventType.ERROR, "Cursor agent timed out")
        raise HTTPException(status_code=504, detail="Cursor agent timed out") from exc
    except (FileNotFoundError, OSError) as exc:
        manager.transition(job.job_id, JobState.FAILED)
        await manager.add_event(job.job_id, EventType.ERROR, f"Cursor CLI not found: {exc}")
        raise HTTPException(status_code=500, detail=f"Cursor CLI not found: {exc}") from exc

    job.session_id = result.session_id
    manager.transition(job.job_id, JobState.ASK_DONE)
    await manager.add_event(job.job_id, EventType.DONE, "Ask completed")
    manager.save_artifact(job.job_id, "ask_response.md", result.text)

    return AskResponse(job_id=job.job_id, ask_text=result.text, session_id=result.session_id)
