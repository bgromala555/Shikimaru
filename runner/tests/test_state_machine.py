"""Tests for the job lifecycle state machine.

Covers every legal transition (should succeed) and representative illegal
transitions (should raise ``InvalidTransitionError``).
"""

import pytest

from runner.models import JobState
from runner.state_machine import InvalidTransitionError, validate_transition


class TestValidTransitions:
    """Verify that all explicitly allowed transitions return True."""

    @pytest.mark.parametrize(
        ("current", "target"),
        [
            (JobState.DRAFT, JobState.ASK_RUNNING),
            (JobState.DRAFT, JobState.PLAN_RUNNING),
            (JobState.ASK_RUNNING, JobState.ASK_DONE),
            (JobState.ASK_RUNNING, JobState.NEEDS_INPUT),
            (JobState.ASK_RUNNING, JobState.FAILED),
            (JobState.NEEDS_INPUT, JobState.ASK_RUNNING),
            (JobState.ASK_DONE, JobState.PLAN_RUNNING),
            (JobState.PLAN_RUNNING, JobState.PLAN_READY),
            (JobState.PLAN_RUNNING, JobState.PLAN_NEEDS_INPUT),
            (JobState.PLAN_RUNNING, JobState.FAILED),
            (JobState.PLAN_NEEDS_INPUT, JobState.PLAN_RUNNING),
            (JobState.PLAN_READY, JobState.APPROVED),
            (JobState.APPROVED, JobState.EXECUTING),
            (JobState.EXECUTING, JobState.COMPLETE),
            (JobState.EXECUTING, JobState.FAILED),
        ],
    )
    def test_allowed_transition(self, current: JobState, target: JobState) -> None:
        """Each legal (current, target) pair should return True without raising.

        Args:
            current: Starting state.
            target: Target state.
        """
        assert validate_transition(current, target) is True


class TestInvalidTransitions:
    """Verify that illegal transitions raise ``InvalidTransitionError``."""

    @pytest.mark.parametrize(
        ("current", "target"),
        [
            # Cannot skip directly to execution
            (JobState.DRAFT, JobState.EXECUTING),
            # Cannot go backwards from done
            (JobState.ASK_DONE, JobState.ASK_RUNNING),
            # Cannot execute without approval
            (JobState.PLAN_READY, JobState.EXECUTING),
            # Terminal states cannot transition
            (JobState.COMPLETE, JobState.DRAFT),
            (JobState.FAILED, JobState.DRAFT),
            # Cannot approve from draft
            (JobState.DRAFT, JobState.APPROVED),
        ],
    )
    def test_invalid_transition_raises(self, current: JobState, target: JobState) -> None:
        """Each illegal (current, target) pair should raise InvalidTransitionError.

        Args:
            current: Starting state.
            target: Target state.
        """
        with pytest.raises(InvalidTransitionError) as exc_info:
            validate_transition(current, target)
        assert exc_info.value.current == current
        assert exc_info.value.target == target
