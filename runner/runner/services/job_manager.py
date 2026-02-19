"""Job manager -- creates jobs, enforces state transitions, and persists artifacts.

The ``JobManager`` is the central orchestration object.  It owns an in-memory
registry of active jobs, validates every state change through the state machine,
and writes artifacts (plan, summary, diff, logs) to disk under the configured
artifacts directory.

An ``asyncio.Queue`` per job allows the SSE endpoint to stream events to the
Android client in real time.
"""

import asyncio
import json
import logging
import uuid
from datetime import UTC, datetime
from pathlib import Path

from runner.models import EventType, Job, JobEvent, JobState
from runner.state_machine import validate_transition

logger = logging.getLogger(__name__)


class JobManager:
    """In-memory job registry with artifact persistence and event streaming.

    Each job is represented by a ``Job`` Pydantic model and has an associated
    ``asyncio.Queue`` for real-time event delivery.

    Attributes:
        artifacts_root: Base directory under which per-job artifact folders
            are created.
    """

    def __init__(self, artifacts_root: Path) -> None:
        """Initialise the job manager.

        Args:
            artifacts_root: Root directory for job artifacts.  Each job gets
                a sub-directory named after its ``job_id``.
        """
        self.artifacts_root = artifacts_root
        self._jobs: dict[str, Job] = {}
        self._queues: dict[str, asyncio.Queue[JobEvent]] = {}

    # ------------------------------------------------------------------
    # Job lifecycle
    # ------------------------------------------------------------------

    def create_job(self, project_path: str) -> Job:
        """Create a new job in the DRAFT state.

        A unique job ID is generated, the artifacts directory is created on
        disk, and an event queue is initialised for SSE streaming.

        Args:
            project_path: Absolute path to the target project folder.

        Returns:
            The newly created ``Job`` record.
        """
        job_id = uuid.uuid4().hex[:12]
        artifacts_dir = self.artifacts_root / job_id
        artifacts_dir.mkdir(parents=True, exist_ok=True)

        now = datetime.now(tz=UTC)
        job = Job(
            job_id=job_id,
            project_path=project_path,
            state=JobState.DRAFT,
            artifacts_dir=artifacts_dir,
            created_at=now,
            updated_at=now,
        )
        self._jobs[job_id] = job
        self._queues[job_id] = asyncio.Queue()
        logger.info("Created job %s for project %s", job_id, project_path)
        return job

    def get_job(self, job_id: str) -> Job:
        """Retrieve a job by its identifier.

        Args:
            job_id: The unique job identifier.

        Returns:
            The matching ``Job`` record.

        Raises:
            KeyError: If no job with the given ID exists.
        """
        if job_id not in self._jobs:
            raise KeyError(f"Job {job_id!r} not found")
        return self._jobs[job_id]

    def get_job_by_plan_id(self, plan_id: str) -> Job:
        """Look up a job by its associated plan identifier.

        Args:
            plan_id: The ``plan_id`` string assigned during plan generation.

        Returns:
            The matching ``Job`` record.

        Raises:
            KeyError: If no job carries the given plan ID.
        """
        for job in self._jobs.values():
            if job.plan_id == plan_id:
                return job
        raise KeyError(f"No job found with plan_id {plan_id!r}")

    def transition(self, job_id: str, target_state: JobState) -> Job:
        """Advance a job to *target_state* if the transition is legal.

        The state machine is consulted first; an ``InvalidTransitionError`` is
        raised for illegal moves.

        Args:
            job_id: The job to transition.
            target_state: The desired new state.

        Returns:
            The updated ``Job`` record.

        Raises:
            KeyError: If the job does not exist.
            InvalidTransitionError: If the transition is illegal.
        """
        job = self.get_job(job_id)
        validate_transition(job.state, target_state)
        job.state = target_state
        job.updated_at = datetime.now(tz=UTC)
        logger.info("Job %s transitioned to %s", job_id, target_state.value)
        return job

    # ------------------------------------------------------------------
    # Events
    # ------------------------------------------------------------------

    async def add_event(self, job_id: str, event_type: EventType, data: str) -> JobEvent:
        """Record a new event and push it onto the job's SSE queue.

        Args:
            job_id: The owning job.
            event_type: Category of the event.
            data: Payload text (log line, step description, error message, etc.).

        Returns:
            The created ``JobEvent`` instance.

        Raises:
            KeyError: If the job does not exist.
        """
        job = self.get_job(job_id)
        event = JobEvent(
            event_type=event_type,
            data=data,
            timestamp=datetime.now(tz=UTC),
        )
        job.events.append(event)
        await self._queues[job_id].put(event)
        return event

    async def get_events(self, job_id: str) -> asyncio.Queue[JobEvent]:
        """Return the asyncio queue for a job so the SSE endpoint can consume events.

        Args:
            job_id: The job whose event queue is requested.

        Returns:
            The ``asyncio.Queue`` instance associated with the job.

        Raises:
            KeyError: If the job does not exist.
        """
        if job_id not in self._queues:
            raise KeyError(f"No event queue for job {job_id!r}")
        return self._queues[job_id]

    # ------------------------------------------------------------------
    # Artifact persistence
    # ------------------------------------------------------------------

    def save_artifact(self, job_id: str, filename: str, content: str) -> Path:
        """Write a text artifact to the job's artifacts directory.

        Args:
            job_id: The owning job.
            filename: Name of the file to create (e.g. ``plan.md``).
            content: Text content to write.

        Returns:
            Absolute path to the written file.

        Raises:
            KeyError: If the job does not exist.
        """
        job = self.get_job(job_id)
        artifact_path = job.artifacts_dir / filename
        artifact_path.write_text(content, encoding="utf-8")
        logger.info("Saved artifact %s for job %s", filename, job_id)
        return artifact_path

    def save_run_metadata(self, job_id: str) -> Path:
        """Persist a ``run.json`` file containing the full job record.

        This is a structured dump of the job's current state, timestamps,
        and event history -- useful for debugging and auditing.

        Args:
            job_id: The owning job.

        Returns:
            Absolute path to the written ``run.json`` file.

        Raises:
            KeyError: If the job does not exist.
        """
        job = self.get_job(job_id)
        payload = job.model_dump(mode="json")
        content = json.dumps(payload, indent=2, default=str)
        return self.save_artifact(job_id, "run.json", content)
