# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Immich is a self-hosted photo and video management solution. This is a **fork** with custom branding/logos. It's a monorepo with multiple services: NestJS backend, SvelteKit web frontend, Flutter mobile app, Python ML service, and a TypeScript CLI.

## Common Commands

### Development Environment
```bash
make dev              # Start full dev stack (Docker Compose with hot-reload)
make dev-down         # Stop dev stack
make dev-update       # Rebuild and start dev stack
```

### Building
```bash
make build-sdk        # Build TypeScript SDK (dependency for web + cli)
make build-server     # Build server (NestJS)
make build-web        # Build web (SvelteKit) — depends on SDK
make build-cli        # Build CLI — depends on SDK
make build-all        # Build all packages
```

### Testing
```bash
# Server (Vitest)
cd server && pnpm run test                                       # Watch mode
cd server && pnpm run test -- --run                              # Run once
cd server && pnpm run test -- src/services/asset.service.spec.ts # Single file
cd server && pnpm run test:cov                                   # Coverage
make test-medium                                                 # Medium tests (Docker)

# Web (Vitest + @testing-library/svelte)
cd web && pnpm run test
cd web && pnpm run test:cov

# CLI
cd cli && pnpm run test

# E2E (Playwright + Vitest)
make e2e
cd e2e && pnpm run test          # Vitest E2E
cd e2e && pnpm run test:web      # Playwright

# ML (pytest)
cd machine-learning && pytest test_main.py

# Everything
make test-all
```

### Linting, Formatting & Type Checking
```bash
make lint-all         # ESLint fix all packages
make format-all       # Prettier fix all packages
make check-all        # TypeScript type-check all packages
make check-web        # svelte-check + tsc on web
```

### Database & OpenAPI
```bash
make sql                      # Regenerate SQL types from schema
make open-api                 # Regenerate all OpenAPI specs and clients
make open-api-typescript      # TypeScript SDK only
make open-api-dart            # Dart client only

# Migrations (from server/)
pnpm run migrations:generate  # Generate migration from schema changes
pnpm run migrations:run       # Apply pending migrations
pnpm run migrations:revert    # Revert last migration
```

## Architecture

### Monorepo Layout

Package manager: **pnpm 10.27+** (workspace monorepo). Node: **24.13.0** (Volta).

| Directory | Package Name | Stack |
|-----------|-------------|-------|
| `server/` | `immich` | NestJS 11, Kysely, PostgreSQL, BullMQ/Redis |
| `web/` | `immich-web` | SvelteKit 2, Svelte 5, TailwindCSS 4 |
| `mobile/` | `immich_mobile` | Flutter 3.35, Dart, Riverpod |
| `machine-learning/` | `immich-ml` | FastAPI, ONNX Runtime, Python 3.11+ |
| `cli/` | `@immich/cli` | Commander.js |
| `open-api/typescript-sdk/` | `@immich/sdk` | Generated from OpenAPI spec |
| `e2e/` | `immich-e2e` | Playwright, Vitest |
| `i18n/` | — | 80+ language translation JSON files |

Web and CLI depend on `@immich/sdk` — build SDK first.

### Server Architecture (NestJS)

Layered architecture with a shared `BaseService` pattern:

- **Controllers** (`server/src/controllers/`): HTTP endpoint mapping, DTO validation
- **Services** (`server/src/services/`): Business logic. All extend `BaseService` which injects every repository
- **Repositories** (`server/src/repositories/`): Data access via Kysely query builder (not an ORM)
- **DTOs** (`server/src/dtos/`): Request/response contracts with `class-validator` + `@ApiProperty()` for OpenAPI
- **Schema** (`server/src/schema/`): Database table definitions and migrations

Background jobs (thumbnails, metadata extraction, ML inference, transcoding) run via **BullMQ/Redis**. The `immich-server` container handles API; `immich-microservices` processes jobs.

### OpenAPI Contract Flow

DTOs → NestJS Swagger generates `immich-openapi-specs.json` → `make open-api` generates TypeScript SDK + Dart client → consumed by web, CLI, and mobile.

**When changing any API endpoint or DTO, run `make open-api` to regenerate clients.**

### Web Frontend (SvelteKit)

- Filesystem routing in `web/src/routes/`
- Shared components in `web/src/lib/components/`
- API via `@immich/sdk`, shared UI via `@immich/ui`
- Real-time updates via Socket.IO
- i18n via `svelte-i18n` with translations in `i18n/`

### Machine Learning Service

- Python FastAPI with ONNX models
- Hardware backends: CPU, CUDA, OpenVINO, RKNN, ArmNN
- Models from HuggingFace Hub
- Used for: CLIP embeddings (smart search), facial recognition, OCR

### Production Docker Compose (`docker/docker-compose.prod.yml`)

| Container | Purpose | Port |
|-----------|---------|------|
| `immich-server` | API + web UI | 80→2283 |
| `immich-machine-learning` | ML inference | 3003 |
| `redis` | Job queue | — |
| `database` | PostgreSQL + vector extensions | 5432 |
| `immich-prometheus` | Metrics (optional) | 9090 |
| `immich-grafana` | Dashboards (optional) | 3000 |

## Code Style

- **Formatting**: Prettier, single quotes, 2-space indent
- **TypeScript**: Strict mode, no `any`, ESLint `--max-warnings 0`
- **Python**: Black + Ruff (line-length 120), Mypy
- **Tests**: Co-located `*.spec.ts` files in server; Vitest everywhere for TS

## Git Config (This Fork)

- **Remote**: `git@github.com:rajulbabel/hobs.git`

## Deployment Plan

This fork is deployed on a **Raspberry Pi 5 (8GB)** on the home WiFi network (simulated locally via Docker-in-Docker for development).

### CI/CD Pipeline
1. Push to fork → GitHub Actions builds multi-arch Docker images (x86 + ARM64)
2. Images pushed to `ghcr.io/rajulbabel/*`
3. Watchtower on the Pi polls every 15 min, auto-pulls and restarts on changes

### Pi Simulator (Local Development)
A Docker Compose setup on the laptop that mimics the Pi:
- `pi` container: Debian with Docker-in-Docker (simulates the Pi)
- `external-hdd` volume: Simulates the USB HDD
- Inside the Pi container: Immich stack + Watchtower

### Target Hardware
- Raspberry Pi 5 (8GB) + case + power supply
- 4-8TB external USB HDD (photos/videos + PostgreSQL data)
- SD card for OS only

### Backup Strategy (future)
- Second external HDD with nightly rsync
- PostgreSQL pg_dump to free cloud storage (Google Drive)
- Optional: rclone to S3 Glacier for offsite photo backup
