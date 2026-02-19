"""Project discovery and creation endpoints.

Scans the configured project root for candidate project folders and returns
them to the Android app so the user can pick which project to work with.
Also supports creating new project folders with Cursor rules pre-configured.
"""

import logging
import re
import shutil
from importlib import resources as importlib_resources
from pathlib import Path

from fastapi import APIRouter, HTTPException, Query

from runner.config import RunnerSettings
from runner.models import CreateProjectRequest, CreateProjectResponse, ProjectsResponse
from runner.services.project_discovery import scan_projects

logger = logging.getLogger(__name__)

router = APIRouter(tags=["projects"])


def _get_template_dir() -> Path:
    """Locate the ``.cursor`` template directory bundled with the runner package.

    Returns:
        Path to the template directory containing ``.cursor/`` scaffolding.

    Raises:
        FileNotFoundError: If the template directory is not found.
    """
    with importlib_resources.as_file(importlib_resources.files("runner.templates")) as templates_path:
        cursor_dir = templates_path / ".cursor"
        if cursor_dir.exists():
            return templates_path
    raise FileNotFoundError("Template directory not found in runner package")


@router.get("/projects", response_model=ProjectsResponse)
async def list_projects(
    days: int = Query(default=10, ge=1, le=365, description="Max age of projects in days"),
) -> ProjectsResponse:
    """List candidate project folders under the configured root.

    Only directories modified within the last *days* days are returned, sorted
    by most-recently-modified first.

    Args:
        days: Look-back window in days.  Defaults to the value in settings but
            can be overridden per-request.

    Returns:
        A ``ProjectsResponse`` containing the discovered project list.
    """
    settings = RunnerSettings()
    projects = scan_projects(settings.project_root, max_age_days=days)
    logger.info("Discovered %d project(s) under %s", len(projects), settings.project_root)
    return ProjectsResponse(projects=projects)


@router.post("/projects", response_model=CreateProjectResponse)
async def create_project(request: CreateProjectRequest) -> CreateProjectResponse:
    """Create a new project folder with Cursor rules pre-configured.

    The folder is created under the configured project root.  A ``.cursor/rules/``
    directory is copied in from the bundled template so the agent has coding
    standards from the first invocation.

    Args:
        request: Contains the desired project folder name.

    Returns:
        A ``CreateProjectResponse`` with the created path.

    Raises:
        HTTPException: If the name is invalid or the folder already exists.
    """
    settings = RunnerSettings()

    safe_name = re.sub(r"[^\w\-. ]", "_", request.name.strip())
    if not safe_name:
        raise HTTPException(status_code=400, detail="Invalid project name")

    project_dir = settings.project_root / safe_name
    if project_dir.exists():
        raise HTTPException(status_code=409, detail=f"Project '{safe_name}' already exists")

    project_dir.mkdir(parents=True, exist_ok=True)
    logger.info("Created project directory: %s", project_dir)

    try:
        template_dir = _get_template_dir()
        cursor_src = template_dir / ".cursor"
        cursor_dst = project_dir / ".cursor"
        shutil.copytree(str(cursor_src), str(cursor_dst))
        logger.info("Copied .cursor template into %s", project_dir)
    except FileNotFoundError:
        logger.warning("No .cursor template found -- project created without rules")

    return CreateProjectResponse(name=safe_name, path=str(project_dir))
