"""Health-check endpoint.

Reports runner status and whether the standalone Cursor agent CLI is
installed.  This is the first endpoint the Android app should hit to verify
connectivity.
"""

import logging

from fastapi import APIRouter

from runner.models import HealthResponse
from runner.services.cursor_invoker import _find_agent_command

logger = logging.getLogger(__name__)

router = APIRouter(tags=["health"])


@router.get("/health", response_model=HealthResponse)
async def health_check() -> HealthResponse:
    """Return runner health status and Cursor agent CLI availability.

    Checks whether the ``agent`` command can be located.  On success, reports
    the resolved command so the caller knows which binary is in use.

    Returns:
        A ``HealthResponse`` indicating the runner's health and agent CLI
        reachability.
    """
    cli_available = False
    cli_version = ""

    try:
        base_cmd = _find_agent_command()
        cli_available = True
        cli_version = f"agent @ {' '.join(base_cmd)}"
    except FileNotFoundError:
        logger.warning("Cursor agent CLI not found")

    status = "ok" if cli_available else "degraded"
    return HealthResponse(status=status, cursor_cli_available=cli_available, cursor_cli_version=cli_version)
