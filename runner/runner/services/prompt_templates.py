"""Prompt template builders for Ask, Plan, and Execute modes.

The standalone ``agent`` CLI handles mode enforcement via ``--mode ask`` and
``--mode plan`` flags, so prompts are kept minimal -- just the user's intent
with light framing.  Heavy system instructions are avoided to prevent confusing
the agent.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from runner.models import HistoryMessage


def _format_history(history: list[HistoryMessage]) -> str:
    """Format conversation history into a readable block for the agent.

    Each message is prefixed with its role so the agent can distinguish between
    user messages and its own prior responses.

    Args:
        history: Ordered list of prior messages in the conversation.

    Returns:
        Formatted string, or empty string if no history.
    """
    if not history:
        return ""

    lines: list[str] = ["Previous conversation:"]
    for msg in history:
        prefix = "User" if msg.role == "user" else "Assistant"
        lines.append(f"[{prefix}]: {msg.content}")
    lines.append("")
    return "\n".join(lines)


def build_ask_prompt(
    user_message: str,
    project_path: str,
    recent_days: int = 10,
    history: list[HistoryMessage] | None = None,
) -> str:
    """Construct the prompt for an Ask-mode invocation.

    Includes conversation history so the agent can maintain context across
    multiple ask rounds.  The ``--mode ask`` flag on the CLI enforces
    read-only behavior.

    Args:
        user_message: The user's free-form question.
        project_path: Absolute path to the project directory.
        recent_days: Hint for Cursor to focus on recently-modified files.
        history: Prior conversation messages for context continuity.

    Returns:
        Complete prompt string.
    """
    context = _format_history(history or [])
    prefix = "Do NOT create, modify, or delete any files. Only answer questions and ask clarifying questions.\n\n"
    if context:
        return f"{prefix}{context}\nCurrent message: {user_message}"
    return f"{prefix}{user_message}"


def build_plan_prompt(
    objective: str,
    project_path: str,
    constraints: list[str] | None = None,
    answers: dict[str, str] | None = None,
    history: list[HistoryMessage] | None = None,
) -> str:
    """Construct the prompt for a Plan-mode invocation.

    Includes conversation history so the agent knows about prior Ask rounds
    and can build a plan informed by earlier clarifications.

    Args:
        objective: The high-level goal the plan should achieve.
        project_path: Absolute path to the project directory.
        constraints: Optional hard constraints to inject into the prompt.
        answers: Optional mapping of question_id -> answer text from a prior
            Ask phase.
        history: Prior conversation messages for context continuity.

    Returns:
        Complete prompt string.
    """
    parts: list[str] = []

    context = _format_history(history or [])
    if context:
        parts.append(context)

    parts.append(f"Create a detailed implementation plan for: {objective}")
    parts.append("Include: Goal, Files to create/modify, Step-by-step implementation, and Commands to run.")

    if constraints:
        formatted = ", ".join(constraints)
        parts.append(f"Constraints: {formatted}")

    if answers:
        formatted = "\n".join(f"  {qid}: {ans}" for qid, ans in answers.items())
        parts.append(f"Answers to prior questions:\n{formatted}")

    return "\n".join(parts)


def build_execute_prompt(plan_markdown: str, project_path: str) -> str:
    """Construct the prompt for an Execute-mode invocation.

    Passes the approved plan directly so the agent implements it.

    Args:
        plan_markdown: The full Markdown text of the approved plan.
        project_path: Absolute path to the project directory.

    Returns:
        Complete prompt string.
    """
    return f"Implement this plan exactly:\n\n{plan_markdown}"
