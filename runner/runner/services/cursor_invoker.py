"""Cursor CLI invoker -- spawns the ``agent`` CLI and returns structured results.

Uses ``subprocess.Popen`` via ``asyncio.to_thread`` to avoid the Windows
``SelectorEventLoop`` limitation (which does not support
``asyncio.create_subprocess_exec``).  This approach works with any event loop
implementation on any platform.

The ``agent`` command is the Cursor Agent CLI.  It authenticates via the
``CURSOR_API_KEY`` environment variable (set in ``.env`` / Docker) so no
browser-based login is required.

Mode flags control what the agent is allowed to do:

- Ask mode: ``--mode ask`` (read-only Q&A)
- Plan mode: ``--mode plan`` (read-only planning)
- Execute mode: ``--yolo`` (full access to implement the plan)
"""

import asyncio
import json
import logging
import shutil
import subprocess
import sys
from collections.abc import AsyncGenerator
from pathlib import Path
from queue import Empty, SimpleQueue

from pydantic import BaseModel, Field

logger = logging.getLogger(__name__)


class AgentResult(BaseModel):
    """Structured result from a single agent CLI invocation.

    Captures the text response and the session identifier needed for
    follow-up calls with ``--resume``.

    Attributes:
        text: The agent's response text.
        session_id: Opaque session identifier for ``--resume``.
        duration_ms: Wall-clock milliseconds reported by the agent.
        is_error: Whether the agent reported an error.
    """

    text: str = Field(description="Agent response text")
    session_id: str = Field(default="", description="Session ID for --resume continuity")
    duration_ms: int = Field(default=0, description="Agent-reported duration in milliseconds")
    is_error: bool = Field(default=False, description="Whether the agent reported an error")


# ---------------------------------------------------------------------------
# Locate the agent CLI
# ---------------------------------------------------------------------------

_WINDOWS = sys.platform == "win32"


def _find_agent_command() -> list[str]:
    """Locate the Cursor ``agent`` CLI and return the base command list.

    Resolution order:

    1. The ``agent`` command on PATH (typical inside Docker or after a standard
       Cursor CLI install on macOS/Linux).
    2. On Windows, scan ``%LOCALAPPDATA%/cursor-agent/versions/`` for the latest
       version directory and use the bundled ``node.exe`` + ``index.js``.

    Returns:
        A list of strings forming the base command (e.g. ``["agent"]`` or
        ``["C:/…/node.exe", "C:/…/index.js"]``).

    Raises:
        FileNotFoundError: If the agent CLI cannot be located.
    """
    agent_path = shutil.which("agent")
    if agent_path:
        return [agent_path]

    if _WINDOWS:
        base = Path.home() / "AppData" / "Local" / "cursor-agent"
        versions_dir = base / "versions"

        if versions_dir.is_dir():
            version_dirs = sorted(
                [d for d in versions_dir.iterdir() if d.is_dir()],
                key=lambda d: d.name,
                reverse=True,
            )
            for vdir in version_dirs:
                node_exe = vdir / "node.exe"
                index_js = vdir / "index.js"
                if node_exe.is_file() and index_js.is_file():
                    return [str(node_exe), str(index_js)]

        if (base / "node.exe").is_file() and (base / "index.js").is_file():
            return [str(base / "node.exe"), str(base / "index.js")]

    install_hint = (
        "Install it with: irm 'https://cursor.com/install?win32=true' | iex"
        if _WINDOWS
        else "Install it with: curl -fsSL https://cursor.com/install | bash"
    )
    raise FileNotFoundError(f"Cursor agent CLI not found. {install_hint}")


def _build_args(
    base_cmd: list[str],
    mode: str,
    session_id: str,
    prompt: str,
    streaming: bool = False,
) -> list[str]:
    """Build the CLI argument list based on invocation mode.

    Args:
        base_cmd: Base command list from ``_find_agent_command()``.
        mode: Agent mode -- ``"ask"``, ``"plan"``, or ``""`` for execute.
        session_id: Session ID to resume, or empty for a new session.
        prompt: The prompt text.
        streaming: If True, use stream-json output for live progress.

    Returns:
        Complete argument list for subprocess execution.
    """
    args = [*base_cmd, "-p", "--trust", "--model", "auto"]

    if streaming:
        args.extend(["--output-format", "stream-json", "--stream-partial-output"])
    else:
        args.extend(["--output-format", "json"])

    if session_id:
        args.extend(["--resume", session_id])

    if mode:
        args.extend(["--mode", mode])
    else:
        args.append("--yolo")

    args.append(prompt)
    return args


# ---------------------------------------------------------------------------
# Blocking subprocess helpers (run in thread via asyncio.to_thread)
# ---------------------------------------------------------------------------


def _run_blocking(args: list[str], project_path: str, timeout_seconds: int) -> tuple[str, int]:
    """Run the agent CLI as a blocking subprocess and return stdout + exit code.

    This runs in a background thread so the async event loop is not blocked.

    Args:
        args: Full argument list including the agent command and all flags.
        project_path: Working directory for the subprocess.
        timeout_seconds: Maximum wall-clock seconds before killing the process.

    Returns:
        Tuple of (stdout_text, return_code).

    Raises:
        TimeoutError: If the process exceeds the timeout.
    """
    try:
        result = subprocess.run(
            args,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            cwd=project_path,
            timeout=timeout_seconds,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
    except subprocess.TimeoutExpired as exc:
        raise TimeoutError(f"Agent CLI timed out after {timeout_seconds}s") from exc

    return result.stdout.strip(), result.returncode


def _stream_blocking(args: list[str], project_path: str, queue: SimpleQueue[str | None]) -> int:
    """Run the agent CLI and push stdout lines into a thread-safe queue.

    Each line is put into the queue as it arrives.  When the process finishes,
    ``None`` is pushed as a sentinel.

    Args:
        args: Full argument list.
        project_path: Working directory for the subprocess.
        queue: Thread-safe queue to receive output lines.

    Returns:
        The subprocess exit code.
    """
    process = subprocess.Popen(
        args,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        cwd=project_path,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    assert process.stdout is not None

    for line in process.stdout:
        stripped = line.rstrip("\n\r")
        if stripped:
            queue.put(stripped)

    process.wait()
    queue.put(None)
    return process.returncode


# ---------------------------------------------------------------------------
# Buffered invocation (ask / plan)
# ---------------------------------------------------------------------------


async def invoke_cursor(
    prompt: str,
    project_path: str,
    cursor_cli_path: str = "agent",
    timeout_seconds: int = 180,
    read_only: bool = False,
    mode: str = "",
    session_id: str = "",
) -> AgentResult:
    """Spawn the agent CLI in buffered JSON mode for ask/plan calls.

    Runs the subprocess in a background thread via ``asyncio.to_thread`` to
    avoid the Windows ``SelectorEventLoop`` subprocess limitation.

    Args:
        prompt: Full prompt text.
        project_path: Absolute path to the project directory.
        cursor_cli_path: Unused legacy parameter (kept for API compatibility).
        timeout_seconds: Maximum seconds before killing the process.
        read_only: Unused legacy parameter (kept for API compatibility).
        mode: Agent mode -- ``"ask"``, ``"plan"``, or ``""`` for execute.
        session_id: Session ID to resume, or empty for a new session.

    Returns:
        An ``AgentResult`` with the response text and session ID.

    Raises:
        TimeoutError: If the agent does not finish in time.
        FileNotFoundError: If the agent CLI is not installed.
    """
    base_cmd = _find_agent_command()
    args = _build_args(base_cmd, mode, session_id, prompt)

    logger.info(
        "Launching agent CLI for %s (mode=%s, resume=%s)",
        project_path,
        mode or "agent",
        session_id[:12] if session_id else "new",
    )

    raw, returncode = await asyncio.to_thread(_run_blocking, args, project_path, timeout_seconds)

    logger.info("Agent CLI exited with code %s, output length %d", returncode, len(raw))

    if not raw:
        return AgentResult(text="(No response from agent)", is_error=True)

    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        logger.warning("Agent returned non-JSON: %s", raw[:200])
        return AgentResult(text=raw)

    return AgentResult(
        text=data.get("result", raw),
        session_id=data.get("session_id", ""),
        duration_ms=data.get("duration_ms", 0),
        is_error=data.get("is_error", False),
    )


# ---------------------------------------------------------------------------
# Streaming invocation (execute)
# ---------------------------------------------------------------------------


async def invoke_cursor_streaming(
    prompt: str,
    project_path: str,
    session_id: str = "",
) -> AsyncGenerator[str, None]:
    """Spawn the agent CLI in streaming mode and yield progress lines.

    Uses a background thread with ``subprocess.Popen`` and a thread-safe
    ``SimpleQueue`` to bridge the blocking readline loop into the async world.
    No timeout is applied -- execute can take as long as it needs.

    Args:
        prompt: Full prompt text.
        project_path: Absolute path to the project directory.
        session_id: Session ID to resume, or empty for a new session.

    Yields:
        Individual progress strings, and a final ``__result__::{json}``
        line with the complete result metadata.

    Raises:
        FileNotFoundError: If the agent CLI is not installed.
    """
    base_cmd = _find_agent_command()
    args = _build_args(base_cmd, mode="", session_id=session_id, prompt=prompt, streaming=True)

    logger.info(
        "Launching streaming agent CLI for %s (resume=%s)",
        project_path,
        session_id[:12] if session_id else "new",
    )

    queue: SimpleQueue[str | None] = SimpleQueue()
    loop = asyncio.get_running_loop()

    reader_future = loop.run_in_executor(None, _stream_blocking, args, project_path, queue)

    while True:
        try:
            line = queue.get_nowait()
        except Empty:
            await asyncio.sleep(0.1)
            continue

        if line is None:
            break

        try:
            chunk = json.loads(line)
        except json.JSONDecodeError:
            yield line
            continue

        chunk_type = chunk.get("type", "")

        if chunk_type == "text_delta":
            text = chunk.get("content", "")
            if text:
                yield text
        elif chunk_type == "result":
            final_text = chunk.get("result", "")
            if final_text:
                yield f"__result__::{json.dumps(chunk)}"
        elif chunk_type == "tool_use":
            tool_name = chunk.get("name", "unknown")
            yield f"[Tool: {tool_name}]"
        elif chunk_type == "tool_result":
            yield "[Tool completed]"
        else:
            raw_text = chunk.get("content", "") or chunk.get("result", "") or str(chunk)
            if raw_text:
                yield raw_text

    returncode = await reader_future
    logger.info("Streaming agent CLI exited with code %s", returncode)
