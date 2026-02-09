# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A bash-based CLI tool (`rails-app-generator.sh`) that generates production-ready, fully dockerized full-stack web applications: Rails API backend + optional React frontend + optional Sidekiq background jobs. Everything runs via Docker Compose with no local Ruby/Node installation required.

## Architecture

**Single-file bash script** (~955 lines) organized into:

1. **Helper functions** — `log_info()`, `log_success()`, `log_warn()`, `log_error()` for colored output; `detect_platform()` for OS detection; `check_docker_available()` for Docker validation
2. **Configuration generators** — `generate_rails_app()`, `configure_database_yml()`, `configure_cors()`, `configure_sidekiq()` — each produces files for the generated project
3. **Main flow** (bottom of script) — parses CLI args, validates inputs, then orchestrates generation: docker-compose.yml → Makefile → Rails API → optional React frontend → optional Sidekiq → git init

Key design decisions:
- **Standalone Docker generation**: Rails app is generated inside a throwaway Docker container (`docker run --rm`) rather than requiring a pre-built image — avoids bootstrapping catch-22
- **Heredoc templates**: All generated files (docker-compose.yml, Makefile, Dockerfiles, configs) are written inline using heredocs with conditional sections
- **Platform-aware permissions**: Uses `-u $(id -u):$(id -g)` on Linux/macOS for correct file ownership from Docker containers

## CLI Options

```
./rails-app-generator.sh <project-name> [options]
  --ruby-version <ver>    (default: 3.4)
  --node-version <ver>    (default: 22)
  --postgres-version <ver> (default: 15)
  --rails-version <ver>   (default: 8.1)
  --redis-version <ver>   (default: 7)
  --react-ts              React + TypeScript frontend
  --react-js              React + JavaScript frontend
  --with-sidekiq          Sidekiq background job processing
```

## Testing & Validation

There is no automated test suite for the generator itself. To validate changes:

```bash
# Syntax check the bash script
bash -n rails-app-generator.sh

# Test generation (creates a project directory)
./rails-app-generator.sh test-app --react-ts --with-sidekiq

# Verify the generated project works
cd test-app && make setup && make up
```

## Code Conventions

- Script uses `set -e` for fail-fast behavior
- Commit messages follow conventional commits (`feat:`, `fix:`, `docs:`, `refactor:`)
- Conditional blocks gate feature-specific generation (React, Sidekiq) throughout the script — when adding a new optional feature, expect to touch: arg parsing, docker-compose.yml generation, Makefile generation, and the main flow section
- YAML anchors (`&app-base`) are used in generated docker-compose.yml for DRY service definitions
