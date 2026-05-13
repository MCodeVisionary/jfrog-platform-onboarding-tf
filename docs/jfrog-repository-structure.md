# JFrog Repository Structure — Best Practices Guide

> **Scope:** This document defines the complete repository structure for all JFrog Projects, covering all package types, lifecycle stages, and per-application repository layouts. It is a companion to the [Projects Best Practices Guide](./jfrog-projects-best-practices.md) and is based on the [JFrog Repository Naming Whitepaper](https://jfrog.com/whitepaper/best-practices-structuring-naming-artifactory-repositories/).

---

## Table of Contents

1. [Naming Convention](#1-naming-convention)
2. [Repository Type Reference](#2-repository-type-reference)
3. [Package Type Registry Reference](#3-package-type-registry-reference)
4. [Repository Layout per Project](#4-repository-layout-per-project)
   - 4.1 [cmrc (payment, catalog)](#41-cmrc--applications-payment--catalog)
   - 4.2 [vntg (design, gateway)](#42-vntg--applications-design--gateway)
   - 4.3 [wlt (stream, store)](#43-wlt--applications-stream--store)
5. [Virtual Repository Resolution Order](#5-virtual-repository-resolution-order)
6. [Stage-to-Repository Access Matrix](#6-stage-to-repository-access-matrix)
7. [Complete Repository Inventory](#7-complete-repository-inventory)
8. [Onboarding — Adding a New Application to a Project](#8-onboarding--adding-a-new-application-to-a-project)

---

## 1. Naming Convention

All repositories follow the JFrog four-part naming structure:

```
{project-key}-{app}-{tech}-{maturity}-{locator}
```

| Part | Description | Values |
|------|-------------|--------|
| `project-key` | JFrog Project Key (product name) | `cmrc`, `vntg`, `wlt` |
| `app` | Application name within the project | `payment`, `catalog`, `design`, `gateway`, `stream`, `store` |
| `tech` | Package type / technology stack | `npm`, `python`, `terraform`, `docker`, `helm` |
| `maturity` | SDLC lifecycle stage | `dev`, `qa`, `prod` |
| `locator` | Physical repository topology | `local`, `remote` (virtual omits this) |

### Rules

- All names are **lowercase** with hyphens (`-`) as separators. No underscores, spaces, or special characters.
- Repository names must be **globally unique** across the platform.
- The Project Key is automatically applied as a prefix to repositories created inside a project, ensuring uniqueness.
- **Remote repositories** are shared at the project level (one per tech) — they proxy a single upstream public registry and do not need to be duplicated per application.
- **Virtual repositories** omit the `locator` suffix — they are topology-agnostic aggregators.

### Naming Patterns at a Glance

| Type | Pattern | Example |
|------|---------|---------|
| Local | `{project}-{app}-{tech}-{stage}-local` | `cmrc-payment-npm-dev-local` |
| Remote | `{project}-{tech}-remote` | `cmrc-npm-remote` |
| Virtual | `{project}-{app}-{tech}-dev` | `cmrc-payment-npm-dev` |

---

## 2. Repository Type Reference

### Local Repository
A physically stored repository where artifacts are published. Each application has **one local repository per technology per stage** (DEV, QA, PROD), giving 3 locals per tech per app.

- CI pipelines **publish** to the DEV local.
- Promotion pipelines **copy/move** artifacts from DEV → QA → PROD locals.
- Only the owning project's WRITE/ADMIN groups can publish to locals.

### Remote Repository
A caching proxy to an external public registry. Remote repositories are **shared at the project level** — one per package type — and are not duplicated per application. All applications within the same project share the same remote proxy.

- Developers and pipelines never hit public registries directly; all external traffic flows through the remote.
- Cached artifacts are stored in the auto-created `{name}-cache` local repository (managed by Artifactory automatically).

### Virtual Repository
A logical aggregation of local and remote repositories, presented as a single developer-facing URL. Virtual repositories exist for **DEV only**. QA and PROD have no virtual — promotion pipelines publish directly to QA and PROD local repositories via OIDC-authenticated CI.

- One virtual per application per technology, fixed to the DEV stage.
- **DEV virtual** — aggregates the DEV local + shared remote (local resolves first). Developers resolve internal builds and external public packages from a single URL.
- **QA and PROD** — no virtual exists. Any tool attempting to resolve from a QA or PROD virtual URL will fail, preventing any unvetted package from entering a promoted stage.
- For CI publishing and promotion, pipelines target local repositories directly — never the virtual.

---

## 3. Package Type Registry Reference

| Tech | JFrog Package Type | Public Remote URL | Notes |
|------|--------------------|-------------------|-------|
| `npm` | npm | `https://registry.npmjs.org` | Standard npm registry |
| `python` | PyPI | `https://pypi.org` | Python Package Index |
| `terraform` | Terraform | `https://registry.terraform.io` | Terraform module & provider registry |
| `docker` | Docker | `https://registry-1.docker.io` | Docker Hub |
| `helm` | Helm | `https://charts.helm.sh/stable` | Helm chart repository |

---

## 4. Repository Layout per Project

Each project section shows:
1. **Local repositories** — per application, per tech, per stage
2. **Remote repositories** — per tech, shared at project level
3. **Virtual repositories** — per application, per tech, **DEV stage only**. Aggregates DEV local + shared remote. QA and PROD have no virtual.

---

### 4.1 cmrc — Applications: payment & catalog

#### Local Repositories

##### Application: payment

| Repository Name | Package Type | Stage | Purpose |
|----------------|-------------|-------|---------|
| `cmrc-payment-npm-dev-local` | npm | DEV | CI-published npm packages for payment |
| `cmrc-payment-npm-qa-local` | npm | QA | Promoted npm packages — passed CI gates |
| `cmrc-payment-npm-prod-local` | npm | PROD | Release-certified npm packages |
| `cmrc-payment-python-dev-local` | PyPI | DEV | CI-published Python packages for payment |
| `cmrc-payment-python-qa-local` | PyPI | QA | Promoted Python packages |
| `cmrc-payment-python-prod-local` | PyPI | PROD | Release-certified Python packages |
| `cmrc-payment-terraform-dev-local` | Terraform | DEV | CI-published Terraform modules for payment |
| `cmrc-payment-terraform-qa-local` | Terraform | QA | Promoted Terraform modules |
| `cmrc-payment-terraform-prod-local` | Terraform | PROD | Release-certified Terraform modules |
| `cmrc-payment-docker-dev-local` | Docker | DEV | CI-built Docker images for payment |
| `cmrc-payment-docker-qa-local` | Docker | QA | Promoted Docker images |
| `cmrc-payment-docker-prod-local` | Docker | PROD | Release Docker images |
| `cmrc-payment-helm-dev-local` | Helm | DEV | CI-published Helm charts for payment |
| `cmrc-payment-helm-qa-local` | Helm | QA | Promoted Helm charts |
| `cmrc-payment-helm-prod-local` | Helm | PROD | Release Helm charts |

##### Application: catalog

| Repository Name | Package Type | Stage | Purpose |
|----------------|-------------|-------|---------|
| `cmrc-catalog-npm-dev-local` | npm | DEV | CI-published npm packages for catalog |
| `cmrc-catalog-npm-qa-local` | npm | QA | Promoted npm packages |
| `cmrc-catalog-npm-prod-local` | npm | PROD | Release-certified npm packages |
| `cmrc-catalog-python-dev-local` | PyPI | DEV | CI-published Python packages for catalog |
| `cmrc-catalog-python-qa-local` | PyPI | QA | Promoted Python packages |
| `cmrc-catalog-python-prod-local` | PyPI | PROD | Release-certified Python packages |
| `cmrc-catalog-terraform-dev-local` | Terraform | DEV | CI-published Terraform modules for catalog |
| `cmrc-catalog-terraform-qa-local` | Terraform | QA | Promoted Terraform modules |
| `cmrc-catalog-terraform-prod-local` | Terraform | PROD | Release-certified Terraform modules |
| `cmrc-catalog-docker-dev-local` | Docker | DEV | CI-built Docker images for catalog |
| `cmrc-catalog-docker-qa-local` | Docker | QA | Promoted Docker images |
| `cmrc-catalog-docker-prod-local` | Docker | PROD | Release Docker images |
| `cmrc-catalog-helm-dev-local` | Helm | DEV | CI-published Helm charts for catalog |
| `cmrc-catalog-helm-qa-local` | Helm | QA | Promoted Helm charts |
| `cmrc-catalog-helm-prod-local` | Helm | PROD | Release Helm charts |

#### Remote Repositories (shared across payment & catalog)

| Repository Name | Package Type | Upstream URL | Purpose |
|----------------|-------------|-------------|---------|
| `cmrc-npm-remote` | npm | registry.npmjs.org | Proxy to public npm registry |
| `cmrc-python-remote` | PyPI | pypi.org | Proxy to Python Package Index |
| `cmrc-terraform-remote` | Terraform | registry.terraform.io | Proxy to Terraform registry |
| `cmrc-docker-remote` | Docker | registry-1.docker.io | Proxy to Docker Hub |
| `cmrc-helm-remote` | Helm | charts.helm.sh/stable | Proxy to Helm chart repository |

#### Virtual Repositories

Virtual repositories aggregate: **stage-specific local + shared remote**, giving developers a single URL per stage.

##### Application: payment

| Repository Name | Package Type | Stage | Aggregates |
|----------------|-------------|-------|-----------|
| `cmrc-payment-npm-dev` | npm | DEV | `cmrc-payment-npm-dev-local` + `cmrc-npm-remote` |
| `cmrc-payment-python-dev` | PyPI | DEV | `cmrc-payment-python-dev-local` + `cmrc-python-remote` |
| `cmrc-payment-terraform-dev` | Terraform | DEV | `cmrc-payment-terraform-dev-local` + `cmrc-terraform-remote` |
| `cmrc-payment-docker-dev` | Docker | DEV | `cmrc-payment-docker-dev-local` + `cmrc-docker-remote` |
| `cmrc-payment-helm-dev` | Helm | DEV | `cmrc-payment-helm-dev-local` + `cmrc-helm-remote` |

##### Application: catalog

| Repository Name | Package Type | Stage | Aggregates |
|----------------|-------------|-------|-----------|
| `cmrc-catalog-npm-dev` | npm | DEV | `cmrc-catalog-npm-dev-local` + `cmrc-npm-remote` |
| `cmrc-catalog-python-dev` | PyPI | DEV | `cmrc-catalog-python-dev-local` + `cmrc-python-remote` |
| `cmrc-catalog-terraform-dev` | Terraform | DEV | `cmrc-catalog-terraform-dev-local` + `cmrc-terraform-remote` |
| `cmrc-catalog-docker-dev` | Docker | DEV | `cmrc-catalog-docker-dev-local` + `cmrc-docker-remote` |
| `cmrc-catalog-helm-dev` | Helm | DEV | `cmrc-catalog-helm-dev-local` + `cmrc-helm-remote` |

---

### 4.2 vntg — Applications: design & gateway

#### Local Repositories

##### Application: design

| Repository Name | Package Type | Stage | Purpose |
|----------------|-------------|-------|---------|
| `vntg-design-npm-dev-local` | npm | DEV | CI-published npm packages for design |
| `vntg-design-npm-qa-local` | npm | QA | Promoted npm packages |
| `vntg-design-npm-prod-local` | npm | PROD | Release-certified npm packages |
| `vntg-design-python-dev-local` | PyPI | DEV | CI-published Python packages for design |
| `vntg-design-python-qa-local` | PyPI | QA | Promoted Python packages |
| `vntg-design-python-prod-local` | PyPI | PROD | Release-certified Python packages |
| `vntg-design-terraform-dev-local` | Terraform | DEV | CI-published Terraform modules for design |
| `vntg-design-terraform-qa-local` | Terraform | QA | Promoted Terraform modules |
| `vntg-design-terraform-prod-local` | Terraform | PROD | Release-certified Terraform modules |
| `vntg-design-docker-dev-local` | Docker | DEV | CI-built Docker images for design |
| `vntg-design-docker-qa-local` | Docker | QA | Promoted Docker images |
| `vntg-design-docker-prod-local` | Docker | PROD | Release Docker images |
| `vntg-design-helm-dev-local` | Helm | DEV | CI-published Helm charts for design |
| `vntg-design-helm-qa-local` | Helm | QA | Promoted Helm charts |
| `vntg-design-helm-prod-local` | Helm | PROD | Release Helm charts |

##### Application: gateway

| Repository Name | Package Type | Stage | Purpose |
|----------------|-------------|-------|---------|
| `vntg-gateway-npm-dev-local` | npm | DEV | CI-published npm packages for gateway |
| `vntg-gateway-npm-qa-local` | npm | QA | Promoted npm packages |
| `vntg-gateway-npm-prod-local` | npm | PROD | Release-certified npm packages |
| `vntg-gateway-python-dev-local` | PyPI | DEV | CI-published Python packages for gateway |
| `vntg-gateway-python-qa-local` | PyPI | QA | Promoted Python packages |
| `vntg-gateway-python-prod-local` | PyPI | PROD | Release-certified Python packages |
| `vntg-gateway-terraform-dev-local` | Terraform | DEV | CI-published Terraform modules for gateway |
| `vntg-gateway-terraform-qa-local` | Terraform | QA | Promoted Terraform modules |
| `vntg-gateway-terraform-prod-local` | Terraform | PROD | Release-certified Terraform modules |
| `vntg-gateway-docker-dev-local` | Docker | DEV | CI-built Docker images for gateway |
| `vntg-gateway-docker-qa-local` | Docker | QA | Promoted Docker images |
| `vntg-gateway-docker-prod-local` | Docker | PROD | Release Docker images |
| `vntg-gateway-helm-dev-local` | Helm | DEV | CI-published Helm charts for gateway |
| `vntg-gateway-helm-qa-local` | Helm | QA | Promoted Helm charts |
| `vntg-gateway-helm-prod-local` | Helm | PROD | Release Helm charts |

#### Remote Repositories (shared across design & gateway)

| Repository Name | Package Type | Upstream URL | Purpose |
|----------------|-------------|-------------|---------|
| `vntg-npm-remote` | npm | registry.npmjs.org | Proxy to public npm registry |
| `vntg-python-remote` | PyPI | pypi.org | Proxy to Python Package Index |
| `vntg-terraform-remote` | Terraform | registry.terraform.io | Proxy to Terraform registry |
| `vntg-docker-remote` | Docker | registry-1.docker.io | Proxy to Docker Hub |
| `vntg-helm-remote` | Helm | charts.helm.sh/stable | Proxy to Helm chart repository |

#### Virtual Repositories

##### Application: design

| Repository Name | Package Type | Stage | Aggregates |
|----------------|-------------|-------|-----------|
| `vntg-design-npm-dev` | npm | DEV | `vntg-design-npm-dev-local` + `vntg-npm-remote` |
| `vntg-design-python-dev` | PyPI | DEV | `vntg-design-python-dev-local` + `vntg-python-remote` |
| `vntg-design-terraform-dev` | Terraform | DEV | `vntg-design-terraform-dev-local` + `vntg-terraform-remote` |
| `vntg-design-docker-dev` | Docker | DEV | `vntg-design-docker-dev-local` + `vntg-docker-remote` |
| `vntg-design-helm-dev` | Helm | DEV | `vntg-design-helm-dev-local` + `vntg-helm-remote` |

##### Application: gateway

| Repository Name | Package Type | Stage | Aggregates |
|----------------|-------------|-------|-----------|
| `vntg-gateway-npm-dev` | npm | DEV | `vntg-gateway-npm-dev-local` + `vntg-npm-remote` |
| `vntg-gateway-python-dev` | PyPI | DEV | `vntg-gateway-python-dev-local` + `vntg-python-remote` |
| `vntg-gateway-terraform-dev` | Terraform | DEV | `vntg-gateway-terraform-dev-local` + `vntg-terraform-remote` |
| `vntg-gateway-docker-dev` | Docker | DEV | `vntg-gateway-docker-dev-local` + `vntg-docker-remote` |
| `vntg-gateway-helm-dev` | Helm | DEV | `vntg-gateway-helm-dev-local` + `vntg-helm-remote` |

---

### 4.3 wlt — Applications: stream & store

#### Local Repositories

##### Application: stream

| Repository Name | Package Type | Stage | Purpose |
|----------------|-------------|-------|---------|
| `wlt-stream-npm-dev-local` | npm | DEV | CI-published npm packages for stream |
| `wlt-stream-npm-qa-local` | npm | QA | Promoted npm packages |
| `wlt-stream-npm-prod-local` | npm | PROD | Release-certified npm packages |
| `wlt-stream-python-dev-local` | PyPI | DEV | CI-published Python packages for stream |
| `wlt-stream-python-qa-local` | PyPI | QA | Promoted Python packages |
| `wlt-stream-python-prod-local` | PyPI | PROD | Release-certified Python packages |
| `wlt-stream-terraform-dev-local` | Terraform | DEV | CI-published Terraform modules for stream |
| `wlt-stream-terraform-qa-local` | Terraform | QA | Promoted Terraform modules |
| `wlt-stream-terraform-prod-local` | Terraform | PROD | Release-certified Terraform modules |
| `wlt-stream-docker-dev-local` | Docker | DEV | CI-built Docker images for stream |
| `wlt-stream-docker-qa-local` | Docker | QA | Promoted Docker images |
| `wlt-stream-docker-prod-local` | Docker | PROD | Release Docker images |
| `wlt-stream-helm-dev-local` | Helm | DEV | CI-published Helm charts for stream |
| `wlt-stream-helm-qa-local` | Helm | QA | Promoted Helm charts |
| `wlt-stream-helm-prod-local` | Helm | PROD | Release Helm charts |

##### Application: store

| Repository Name | Package Type | Stage | Purpose |
|----------------|-------------|-------|---------|
| `wlt-store-npm-dev-local` | npm | DEV | CI-published npm packages for store |
| `wlt-store-npm-qa-local` | npm | QA | Promoted npm packages |
| `wlt-store-npm-prod-local` | npm | PROD | Release-certified npm packages |
| `wlt-store-python-dev-local` | PyPI | DEV | CI-published Python packages for store |
| `wlt-store-python-qa-local` | PyPI | QA | Promoted Python packages |
| `wlt-store-python-prod-local` | PyPI | PROD | Release-certified Python packages |
| `wlt-store-terraform-dev-local` | Terraform | DEV | CI-published Terraform modules for store |
| `wlt-store-terraform-qa-local` | Terraform | QA | Promoted Terraform modules |
| `wlt-store-terraform-prod-local` | Terraform | PROD | Release-certified Terraform modules |
| `wlt-store-docker-dev-local` | Docker | DEV | CI-built Docker images for store |
| `wlt-store-docker-qa-local` | Docker | QA | Promoted Docker images |
| `wlt-store-docker-prod-local` | Docker | PROD | Release Docker images |
| `wlt-store-helm-dev-local` | Helm | DEV | CI-published Helm charts for store |
| `wlt-store-helm-qa-local` | Helm | QA | Promoted Helm charts |
| `wlt-store-helm-prod-local` | Helm | PROD | Release Helm charts |

#### Remote Repositories (shared across stream & store)

| Repository Name | Package Type | Upstream URL | Purpose |
|----------------|-------------|-------------|---------|
| `wlt-npm-remote` | npm | registry.npmjs.org | Proxy to public npm registry |
| `wlt-python-remote` | PyPI | pypi.org | Proxy to Python Package Index |
| `wlt-terraform-remote` | Terraform | registry.terraform.io | Proxy to Terraform registry |
| `wlt-docker-remote` | Docker | registry-1.docker.io | Proxy to Docker Hub |
| `wlt-helm-remote` | Helm | charts.helm.sh/stable | Proxy to Helm chart repository |

#### Virtual Repositories

##### Application: stream

| Repository Name | Package Type | Stage | Aggregates |
|----------------|-------------|-------|-----------|
| `wlt-stream-npm-dev` | npm | DEV | `wlt-stream-npm-dev-local` + `wlt-npm-remote` |
| `wlt-stream-python-dev` | PyPI | DEV | `wlt-stream-python-dev-local` + `wlt-python-remote` |
| `wlt-stream-terraform-dev` | Terraform | DEV | `wlt-stream-terraform-dev-local` + `wlt-terraform-remote` |
| `wlt-stream-docker-dev` | Docker | DEV | `wlt-stream-docker-dev-local` + `wlt-docker-remote` |
| `wlt-stream-helm-dev` | Helm | DEV | `wlt-stream-helm-dev-local` + `wlt-helm-remote` |

##### Application: store

| Repository Name | Package Type | Stage | Aggregates |
|----------------|-------------|-------|-----------|
| `wlt-store-npm-dev` | npm | DEV | `wlt-store-npm-dev-local` + `wlt-npm-remote` |
| `wlt-store-python-dev` | PyPI | DEV | `wlt-store-python-dev-local` + `wlt-python-remote` |
| `wlt-store-terraform-dev` | Terraform | DEV | `wlt-store-terraform-dev-local` + `wlt-terraform-remote` |
| `wlt-store-docker-dev` | Docker | DEV | `wlt-store-docker-dev-local` + `wlt-docker-remote` |
| `wlt-store-helm-dev` | Helm | DEV | `wlt-store-helm-dev-local` + `wlt-helm-remote` |

---

## 5. Virtual Repository Resolution Order

Virtual repositories exist for **DEV only**. QA and PROD have no virtual repository — pipelines publish directly to those local repositories via OIDC-authenticated CI.

### DEV virtual — local + remote

```
Virtual: {project}-{app}-{tech}-dev
  Resolution Order:
    1. {project}-{app}-{tech}-dev-local    ← internal dev builds first
    2. {project}-{tech}-remote             ← public registry fallback
```

The local repository always resolves first. If an artifact exists in the DEV local (e.g. a CI-published build), it is returned immediately without hitting the remote. If not found, Artifactory falls back to the remote cache and fetches from the public registry.

### QA and PROD — no virtual

QA and PROD have no virtual repository. Pipelines that promote artifacts to QA or PROD do so by publishing directly to the corresponding local repository using OIDC credentials scoped to that stage. There is no URL through which a developer or pipeline could accidentally pull an external package into a QA or PROD environment.

### Why removing QA/PROD virtuals is stronger than the remote-exclusion-only approach

Even a virtual repository that excludes the remote still creates a resolvable URL endpoint for QA/PROD. Removing the virtual entirely means:

- There is no URL to misconfigure — a pipeline cannot accidentally point at a QA/PROD virtual that was later given a remote.
- Developers receive a clear 404 if they attempt to resolve directly from a QA/PROD path, making the boundary explicit.
- The attack surface for dependency confusion at promoted stages is zero.

### Summary by stage

| Stage | Virtual exists | Resolution | Who publishes |
|-------|---------------|------------|---------------|
| DEV | Yes — `{project}-{app}-{tech}-dev` | DEV local → remote fallback | CI via OIDC, WRITE group |
| QA | No | Direct to QA local only | Promotion pipeline via OIDC |
| PROD | No | Direct to PROD local only | Promotion pipeline via OIDC |

---

## 6. Stage-to-Repository Access Matrix

This table shows who can read and write to each repository type and stage. Permissions flow from the IDP group → JFrog role → stage access (as defined in the Projects Best Practices Guide).

| Repository | Type | Stage | ADMIN group | WRITE group | READ group | CI (OIDC) |
|-----------|------|-------|-------------|-------------|------------|-----------|
| `{p}-{a}-{tech}-dev-local` | Local | DEV | R/W | R/W | — | R/W (publish) |
| `{p}-{a}-{tech}-qa-local` | Local | QA | R/W | R | — | R/W (promote) |
| `{p}-{a}-{tech}-prod-local` | Local | PROD | R/W | R | — | R/W (promote) |
| `{p}-{tech}-remote` | Remote | — | R/W | R | R | R |
| `{p}-{a}-{tech}-dev` | Virtual | DEV | R/W | R/W | R | R/W |

**Legend:** R = Read, W = Write, `—` = No direct access (DEV access via virtual only)

> **Key rule:** The READ group resolves DEV packages exclusively through the DEV virtual repository. For QA and PROD, only ADMIN groups and OIDC-authenticated CI pipelines have any access — there is no virtual URL for consumers to inadvertently reach.

---

## 7. Complete Repository Inventory

### Repository Counts Per Project

| Project | Apps | Local Repos | Remote Repos | Virtual Repos | Total |
|---------|------|-------------|--------------|---------------|-------|
| cmrc | payment, catalog | 30 | 5 | 10 | 45 |
| vntg | design, gateway | 30 | 5 | 10 | 45 |
| wlt | stream, store | 30 | 5 | 10 | 45 |
| **Total** | **6** | **90** | **15** | **30** | **135** |

### Per-App Breakdown (applies equally to all apps)

| Repo Type | Count | Calculation |
|-----------|-------|-------------|
| Local | 15 | 5 techs × 3 stages |
| Remote | 5 (shared) | 5 techs × 1 (project-shared) |
| Virtual | 5 | 5 techs × 1 stage (DEV only) |
| **Total per app** | **25** | (remotes shared with sibling apps) |

---

## 8. Onboarding — Adding a New Application to a Project

When a new application (e.g., `invoice`) is added to an existing project (e.g., `cmrc`), the Project Admin follows this checklist:

### Local Repositories to Create (15 total)

For each of the 5 package types, create 3 local repositories:

```
cmrc-invoice-npm-dev-local
cmrc-invoice-npm-qa-local
cmrc-invoice-npm-prod-local

cmrc-invoice-python-dev-local
cmrc-invoice-python-qa-local
cmrc-invoice-python-prod-local

cmrc-invoice-terraform-dev-local
cmrc-invoice-terraform-qa-local
cmrc-invoice-terraform-prod-local

cmrc-invoice-docker-dev-local
cmrc-invoice-docker-qa-local
cmrc-invoice-docker-prod-local

cmrc-invoice-helm-dev-local
cmrc-invoice-helm-qa-local
cmrc-invoice-helm-prod-local
```

### Remote Repositories

No new remotes are needed. The new application reuses the existing project-level remotes:

```
cmrc-npm-remote       ← already exists
cmrc-python-remote    ← already exists
cmrc-terraform-remote ← already exists
cmrc-docker-remote    ← already exists
cmrc-helm-remote      ← already exists
```

### Virtual Repositories to Create (5 total — DEV only)

Virtual repositories exist for DEV only. QA and PROD have no virtual — promotion pipelines write directly to those locals.

```
DEV virtuals (local + remote):
cmrc-invoice-npm-dev       → cmrc-invoice-npm-dev-local + cmrc-npm-remote
cmrc-invoice-python-dev    → cmrc-invoice-python-dev-local + cmrc-python-remote
cmrc-invoice-terraform-dev → cmrc-invoice-terraform-dev-local + cmrc-terraform-remote
cmrc-invoice-docker-dev    → cmrc-invoice-docker-dev-local + cmrc-docker-remote
cmrc-invoice-helm-dev      → cmrc-invoice-helm-dev-local + cmrc-helm-remote
```

### Stage Mapping

- Assign each new local repository to its corresponding JFrog Project Stage (DEV / QA / PROD) in the project settings.
- Verify the WRITE group has deploy permissions on the DEV locals.
- Verify promotion pipelines (OIDC-authenticated) have deploy permissions on QA and PROD locals.

---

## References

- [JFrog Best Practices for Structuring and Naming Artifactory Repositories](https://jfrog.com/whitepaper/best-practices-structuring-naming-artifactory-repositories/)
- [JFrog Projects Best Practices](https://docs.jfrog.com/projects/docs/projects-best-practices)
- [Projects Setup Best Practices](https://docs.jfrog.com/projects/docs/projects-setup-best-practices)
- [Local Repositories](https://docs.jfrog.com/artifactory/docs/local-repositories)
- [Remote Repositories](https://docs.jfrog.com/artifactory/docs/remote-repositories)
- [Virtual Repositories](https://docs.jfrog.com/artifactory/docs/virtual-repositories)
- [Stages & Lifecycle](https://docs.jfrog.com/administration/docs/stages-lifecycle)
