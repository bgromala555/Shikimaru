"""FastAPI application entry point for the Shikigami runner service.

This module creates the FastAPI ``app`` instance, registers all routers, and
wires the shared ``JobManager`` into each router module.  The server is started
via ``uvicorn`` using the settings from ``runner.config``.

The runner also serves the Flutter web build as a PWA so users can access the
full Shikigami UI from any browser — including iOS Safari with home-screen
install support.
"""

import logging
from pathlib import Path

import uvicorn
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import RedirectResponse
from fastapi.staticfiles import StaticFiles

from runner.config import RunnerSettings
from runner.routers import approve, ask, events, execute, health, plan, projects
from runner.services.job_manager import JobManager

WEB_APP_DIR = Path(__file__).resolve().parent.parent / "web_app"

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger(__name__)


def create_app() -> FastAPI:
    """Build and configure the FastAPI application.

    Registers all API routers, sets up CORS for local-network Android access,
    and initialises the shared ``JobManager`` that every router depends on.

    Returns:
        A fully configured ``FastAPI`` application ready to serve.
    """
    settings = RunnerSettings()

    app = FastAPI(
        title="Shikigami Runner",
        description="Local desktop service that orchestrates the Cursor Agent CLI for remote Android control",
        version="0.1.0",
    )

    # Allow the Android app (running on a different host on the local network)
    # to make requests without CORS issues.
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    # Shared job manager -- all routers reference the same instance
    job_manager = JobManager(artifacts_root=settings.artifacts_dir)

    # Wire the manager into each router that needs it
    ask.set_job_manager(job_manager)
    plan.set_job_manager(job_manager)
    approve.set_job_manager(job_manager)
    execute.set_job_manager(job_manager)
    events.set_job_manager(job_manager)

    # Register routers
    app.include_router(health.router)
    app.include_router(projects.router)
    app.include_router(ask.router)
    app.include_router(plan.router)
    app.include_router(approve.router)
    app.include_router(execute.router)
    app.include_router(events.router)

    # Serve the Flutter web PWA when the build directory exists.
    # Mounted last so API routes always take priority.
    if WEB_APP_DIR.is_dir():
        app.mount("/app", StaticFiles(directory=str(WEB_APP_DIR), html=True), name="web_app")

        @app.get("/")
        async def _redirect_root() -> RedirectResponse:
            """Redirect the bare root URL to the web app."""
            return RedirectResponse(url="/app/")

        logger.info("Web PWA mounted from %s", WEB_APP_DIR)
    else:
        logger.warning("Web app directory not found at %s -- PWA disabled", WEB_APP_DIR)

    logger.info(
        "Shikigami runner initialised -- project_root=%s, artifacts=%s",
        settings.project_root,
        settings.artifacts_dir,
    )
    return app


app = create_app()


def main() -> None:
    """Start the Uvicorn server with settings from the environment.

    This is the CLI entry point (``python -m runner.main``).
    """
    settings = RunnerSettings()
    logger.info("Starting Shikigami runner on %s:%d", settings.host, settings.port)
    uvicorn.run(
        "runner.main:app",
        host=settings.host,
        port=settings.port,
        reload=False,
    )


if __name__ == "__main__":
    main()
