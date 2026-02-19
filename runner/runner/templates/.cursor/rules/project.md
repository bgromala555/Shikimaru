# Project Rules

## Technical Standards
- Use Python 3.12+ syntax
- Use type hints on all functions
- Use async/await for asynchronous operations
- Implement proper error handling and exception handling
- Prefer `pathlib.Path` over `os.path` for path operations
- Use `logging` module instead of `print()`
- Use builtin types (`list[int]`, `dict[str, int]`) over `typing` equivalents
- Prefer Pydantic BaseModel over plain dicts for data structures

## Code Style
- Follow PEP8 and Ruff formatting guidelines
- Set line length to 140 characters
- Use guard clauses with early returns instead of deeply nested code
- Keep functions small and focused on a single responsibility
- Every function must have a detailed docstring (Google-style)
- Docstrings must describe parameters, return values, and raised exceptions

## Code Quality
After every code change, run these in order:
```bash
black --preview --line-length 140 .
ruff check --preview --fix .
mypy .
```
All must pass with zero errors.

## Package Management
- Use `uv` for dependency management (never `pip install`)
- Use virtual environments (`.venv/`)
- Run scripts with `uv run` or `.venv/bin/python`

## Project Structure
- Prefer functions in modules over OOP (classes are fine when they make sense)
- Keep components focused and well-organized
- Never save scripts to the project root
- Use standalone `pytest.ini` for test configuration
