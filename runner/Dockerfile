FROM python:3.12-slim AS base

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Install system dependencies needed by the Cursor agent CLI installer
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install uv for fast dependency management
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# Copy dependency file first for layer caching
COPY pyproject.toml ./

# Install production dependencies only
RUN uv pip install --system --no-cache .

# Copy application source
COPY runner/ runner/

# Default environment variables -- override at runtime
ENV RUNNER_HOST=0.0.0.0 \
    RUNNER_PORT=8423 \
    RUNNER_PROJECT_ROOT=/projects \
    RUNNER_ARTIFACTS_DIR=/data/jobs

EXPOSE 8423

# Create directories for mounted volumes and set ownership
RUN mkdir -p /projects /data/jobs \
    && useradd --create-home appuser \
    && chown -R appuser:appuser /projects /data/jobs

# Switch to non-root user, then install Cursor agent CLI into their home dir.
# The CLI authenticates via CURSOR_API_KEY env var at runtime -- no browser needed.
USER appuser
RUN curl -fsSL https://cursor.com/install | bash

CMD ["python", "-m", "runner.main"]
