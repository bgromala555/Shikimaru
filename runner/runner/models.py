"""Pydantic models for all Cursor Runner API contracts and internal data structures.

This module defines every request body, response body, and internal record used by the
runner service.  All structured data flows through these models -- no loose dicts.
"""

from __future__ import annotations

import enum
from datetime import datetime
from pathlib import Path

from pydantic import BaseModel, Field

# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------


class JobState(enum.StrEnum):
    """All possible states a job can occupy in its lifecycle.

    The runner enforces a strict state machine -- only certain transitions are
    legal.  See ``runner.state_machine`` for the transition table.
    """

    DRAFT = "draft"
    ASK_RUNNING = "ask_running"
    ASK_DONE = "ask_done"
    NEEDS_INPUT = "needs_input"
    PLAN_RUNNING = "plan_running"
    PLAN_READY = "plan_ready"
    PLAN_NEEDS_INPUT = "plan_needs_input"
    APPROVED = "approved"
    EXECUTING = "executing"
    COMPLETE = "complete"
    FAILED = "failed"


class EventType(enum.StrEnum):
    """Categories of server-sent events emitted during job execution."""

    STEP = "step"
    LOG = "log"
    DONE = "done"
    ERROR = "error"


# ---------------------------------------------------------------------------
# Project discovery
# ---------------------------------------------------------------------------


class ProjectInfo(BaseModel):
    """Metadata for a single discovered project folder.

    Returned as part of the ``GET /projects`` response so the Android app can
    display a selectable project list.
    """

    name: str = Field(description="Human-readable project folder name")
    path: str = Field(description="Absolute path to the project folder on disk")
    last_modified: datetime = Field(description="Most-recent modification timestamp of the folder")
    file_count: int = Field(description="Number of files (non-recursive) inside the folder")


class ProjectsResponse(BaseModel):
    """Response payload for ``GET /projects``.

    Contains a flat list of candidate project folders discovered under the
    configured project root directory.
    """

    projects: list[ProjectInfo] = Field(default_factory=list, description="Discovered project folders")


class CreateProjectRequest(BaseModel):
    """Request body for ``POST /projects``.

    Creates a new project folder under the configured project root.
    """

    name: str = Field(description="Name for the new project folder")


class CreateProjectResponse(BaseModel):
    """Response payload for ``POST /projects``."""

    name: str = Field(description="Created project folder name")
    path: str = Field(description="Absolute path to the created project folder")


# ---------------------------------------------------------------------------
# Health
# ---------------------------------------------------------------------------


class HealthResponse(BaseModel):
    """Response payload for ``GET /health``.

    Reports runner status and whether the Cursor CLI is reachable.
    """

    status: str = Field(description="Runner health status string, e.g. 'ok' or 'degraded'")
    cursor_cli_available: bool = Field(description="True when 'cursor --version' succeeds")
    cursor_cli_version: str = Field(default="", description="Reported Cursor CLI version string")


# ---------------------------------------------------------------------------
# Ask
# ---------------------------------------------------------------------------


class AskContext(BaseModel):
    """Optional context hints supplied alongside an Ask request.

    Allows the caller to scope Cursor's attention to recently-changed files.
    """

    recent_days: int = Field(default=10, description="Only consider files modified in the last N days")


class HistoryMessage(BaseModel):
    """A single message from the conversation history.

    Included in Ask and Plan requests so the agent has context from
    prior exchanges in the same session.
    """

    role: str = Field(description="Either 'user' or 'assistant'")
    content: str = Field(description="Message text")


class AskRequest(BaseModel):
    """Request body for ``POST /ask``.

    Sends a free-form question to Cursor in read-only mode so the user can
    clarify requirements before generating a plan.
    """

    project_path: str = Field(description="Absolute path to the target project folder")
    message: str = Field(description="The user's question or prompt")
    context: AskContext = Field(default_factory=AskContext, description="Optional scoping context")
    history: list[HistoryMessage] = Field(default_factory=list, description="Prior conversation messages for context")
    session_id: str = Field(default="", description="Agent session ID to resume for conversation continuity")


class QuestionOption(BaseModel):
    """A single selectable option inside a clarification question.

    When Cursor responds with questions, each question can carry pre-defined
    answer choices (A / B / C / D style).
    """

    label: str = Field(description="Short option label, e.g. 'A'")
    text: str = Field(description="Full description of the option")


class ClarificationQuestion(BaseModel):
    """A follow-up question that Cursor asks the user during Ask or Plan phases.

    May include pre-defined options or accept free-text answers.
    """

    question_id: str = Field(description="Stable identifier for this question")
    text: str = Field(description="The question text")
    options: list[QuestionOption] = Field(default_factory=list, description="Pre-defined answer choices, if any")


class AskResponse(BaseModel):
    """Response payload for ``POST /ask``.

    Contains Cursor's textual answer and any follow-up questions it wants the
    user to address before planning begins.
    """

    job_id: str = Field(description="Identifier for the created job")
    ask_text: str = Field(description="Cursor's response text")
    session_id: str = Field(default="", description="Agent session ID for conversation continuity")
    questions: list[ClarificationQuestion] = Field(default_factory=list, description="Follow-up questions, if any")


# ---------------------------------------------------------------------------
# Plan
# ---------------------------------------------------------------------------


class PlanRequest(BaseModel):
    """Request body for ``POST /plan``.

    Instructs the runner to generate a Markdown plan via Cursor's plan mode.
    The caller may include answers to previously-asked clarification questions.
    """

    project_path: str = Field(description="Absolute path to the target project folder")
    objective: str = Field(description="High-level goal for the plan")
    constraints: list[str] = Field(default_factory=list, description="Hard constraints to include in the prompt")
    answers: dict[str, str] = Field(default_factory=dict, description="Answers keyed by question_id from a prior Ask")
    history: list[HistoryMessage] = Field(default_factory=list, description="Prior conversation messages for context")
    session_id: str = Field(default="", description="Agent session ID to resume for conversation continuity")


class PlanResponse(BaseModel):
    """Response payload for ``POST /plan``.

    Contains the generated plan Markdown and any new questions that arose
    during plan generation.
    """

    job_id: str = Field(description="Identifier for the job")
    plan_id: str = Field(description="Unique identifier for this plan artifact")
    plan_markdown: str = Field(description="Full Markdown text of the generated plan")
    session_id: str = Field(default="", description="Agent session ID for conversation continuity")
    questions: list[ClarificationQuestion] = Field(default_factory=list, description="Follow-up questions, if any")


# ---------------------------------------------------------------------------
# Approve / Execute
# ---------------------------------------------------------------------------


class ApproveRequest(BaseModel):
    """Request body for ``POST /approve``.

    Transitions the job from PLAN_READY to APPROVED so execution can begin.
    """

    plan_id: str = Field(description="The plan_id to approve")


class ApproveResponse(BaseModel):
    """Response payload for ``POST /approve``."""

    job_id: str = Field(description="Identifier for the job")
    status: str = Field(description="Confirmation message, e.g. 'approved'")


class ExecuteRequest(BaseModel):
    """Request body for ``POST /execute``.

    Triggers Cursor to implement the approved plan.  Execution cannot proceed
    unless the plan has been explicitly approved.
    """

    plan_id: str = Field(description="The plan_id to execute")


class ExecuteResponse(BaseModel):
    """Response payload for ``POST /execute``."""

    job_id: str = Field(description="Identifier for the execution job")


class JobStatusResponse(BaseModel):
    """Response payload for ``GET /job-status`` -- lightweight polling endpoint.

    The Android client polls this to track execution progress when SSE is
    unreliable over mobile Wi-Fi connections.
    """

    job_id: str = Field(description="Job identifier")
    state: str = Field(description="Current job state value")
    event_count: int = Field(description="Total number of events emitted so far")
    latest_event: str = Field(default="", description="Data from the most recent event")


# ---------------------------------------------------------------------------
# SSE events
# ---------------------------------------------------------------------------


class JobEvent(BaseModel):
    """A single server-sent event emitted during job execution.

    The ``GET /events?job_id=...`` SSE endpoint yields a stream of these.
    """

    event_type: EventType = Field(description="Category of this event")
    data: str = Field(description="Event payload -- log line, step description, or error message")
    timestamp: datetime = Field(default_factory=datetime.utcnow, description="UTC timestamp when the event was created")


# ---------------------------------------------------------------------------
# Internal job record (not directly exposed as API response)
# ---------------------------------------------------------------------------


class Job(BaseModel):
    """Internal record representing a single orchestration job.

    Tracks the current state, associated artifacts, and a backlog of events
    that have been emitted so far.  Stored in-memory by the ``JobManager``.
    """

    job_id: str = Field(description="Unique job identifier")
    project_path: str = Field(description="Absolute path to the target project")
    state: JobState = Field(default=JobState.DRAFT, description="Current state in the lifecycle")
    session_id: str = Field(default="", description="Agent CLI session ID for --resume continuity")
    plan_id: str = Field(default="", description="Associated plan identifier, if any")
    plan_markdown: str = Field(default="", description="Stored plan Markdown text")
    artifacts_dir: Path = Field(default=Path("."), description="Directory where job artifacts are persisted")
    events: list[JobEvent] = Field(default_factory=list, description="Chronological list of emitted events")
    created_at: datetime = Field(default_factory=datetime.utcnow, description="Job creation timestamp")
    updated_at: datetime = Field(default_factory=datetime.utcnow, description="Last state-change timestamp")
