# Architecture Patterns — Recon Reference

Common architecture patterns to identify during codebase reconnaissance.

## MVC (Model-View-Controller)

**Signals:** `app/Models/`, `app/Controllers/`, `resources/views/`, `routes/`
**Frameworks:** Laravel, Rails, Django, Spring MVC, ASP.NET MVC

## DDD / Vertical Slice

**Signals:** `app/Domain/`, `app/Pages/`, `app/Modules/`, feature-based directory grouping
**Frameworks:** Laravel (custom), NestJS modules, Go services

## Clean Architecture / Hexagonal

**Signals:** `domain/`, `application/`, `infrastructure/`, `ports/`, `adapters/`
**Frameworks:** Framework-agnostic, common in Java/Kotlin, Go

## Monorepo — Multi-service

**Signals:** Multiple `package.json` / `composer.json` at different paths, `packages/`, `services/`, `apps/`
**Tools:** Turborepo, Nx, Lerna, custom

## Flat / Script-based

**Signals:** All files in root or single `src/` directory, no clear separation
**Common in:** Small CLIs, utilities, scripts, early-stage projects

## Serverless / Function-based

**Signals:** `functions/`, `lambdas/`, `serverless.yml`, `sam.yaml`, `vercel.json`
**Platforms:** AWS Lambda, Vercel, Cloudflare Workers, Google Cloud Functions

## Microservices (single service in repo)

**Signals:** Single `Dockerfile`, single API entry point, queue consumers, health endpoint
**Common in:** Go, Node.js, PHP services behind API gateways
