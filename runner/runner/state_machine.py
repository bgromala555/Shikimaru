"""Job lifecycle state machine with strict transition validation.

The runner enforces a deterministic workflow: jobs must progress through a
well-defined sequence of states.  Any illegal transition is rejected with an
``InvalidTransitionError`` so that, for example, execution can never begin
without an explicit plan approval.
"""

from runner.models import JobState

# Explicit map of every legal transition.  If a (current, target) pair is not
# present here, the transition is forbidden.
ALLOWED_TRANSITIONS: dict[JobState, frozenset[JobState]] = {
    JobState.DRAFT: frozenset({JobState.ASK_RUNNING, JobState.PLAN_RUNNING}),
    JobState.ASK_RUNNING: frozenset({JobState.ASK_DONE, JobState.NEEDS_INPUT, JobState.FAILED}),
    JobState.NEEDS_INPUT: frozenset({JobState.ASK_RUNNING}),
    JobState.ASK_DONE: frozenset({JobState.PLAN_RUNNING}),
    JobState.PLAN_RUNNING: frozenset({JobState.PLAN_READY, JobState.PLAN_NEEDS_INPUT, JobState.FAILED}),
    JobState.PLAN_NEEDS_INPUT: frozenset({JobState.PLAN_RUNNING}),
    JobState.PLAN_READY: frozenset({JobState.APPROVED}),
    JobState.APPROVED: frozenset({JobState.EXECUTING}),
    JobState.EXECUTING: frozenset({JobState.COMPLETE, JobState.FAILED}),
    JobState.COMPLETE: frozenset(),
    JobState.FAILED: frozenset(),
}


class InvalidTransitionError(Exception):
    """Raised when a caller attempts an illegal job-state transition.

    Attributes:
        current: The state the job is currently in.
        target: The state the caller attempted to transition to.
    """

    def __init__(self, current: JobState, target: JobState) -> None:
        self.current = current
        self.target = target
        super().__init__(f"Transition from {current.value!r} to {target.value!r} is not allowed")


def validate_transition(current: JobState, target: JobState) -> bool:
    """Check whether transitioning from *current* to *target* is legal.

    If the transition is allowed the function returns ``True``.  If it is
    forbidden an ``InvalidTransitionError`` is raised -- the function never
    returns ``False`` so callers do not need to handle that branch.

    Args:
        current: The state the job occupies right now.
        target: The desired next state.

    Returns:
        ``True`` when the transition is permitted.

    Raises:
        InvalidTransitionError: When the transition violates the state machine.
    """
    allowed = ALLOWED_TRANSITIONS.get(current, frozenset())
    if target not in allowed:
        raise InvalidTransitionError(current, target)
    return True
