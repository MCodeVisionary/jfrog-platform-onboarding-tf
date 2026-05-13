# JFrog Platform — Projects Best Practices Guide

> **Scope:** This document defines the canonical standards for structuring JFrog Projects, lifecycle stages, Identity Provider (IDP) group integration, and role-based access control (RBAC) across all product teams. The examples in this guide use the **cmrc**, **vntg**, and **wlt** product lines.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Global Lifecycle Stages](#2-global-lifecycle-stages)
3. [Project Structure — One Project Per Product](#3-project-structure--one-project-per-product)
4. [Identity Provider (IDP) Group Naming Convention](#4-identity-provider-idp-group-naming-convention)
5. [User-to-Group Mapping (IDP)](#5-user-to-group-mapping-idp)
6. [Group-to-Role Mapping Inside JFrog Projects](#6-group-to-role-mapping-inside-jfrog-projects)
7. [Project Admin Group](#7-project-admin-group)
8. [Repository Naming Convention](#8-repository-naming-convention)
9. [Full Reference — cmrc, vntg, wlt](#9-full-reference--cmrc-vntg-wlt)
10. [Onboarding a New Product Team](#10-onboarding-a-new-product-team)
11. [Quick Reference Table](#11-quick-reference-table)

---

## 1. Architecture Overview

The JFrog Platform is organised around three pillars:

```
JFrog Platform
│
├── Global Stages (Platform Admin–managed, inherited by all projects)
│   ├── DEV
│   ├── QA
│   └── PROD
│
├── Projects (one per product, Platform Admin creates, Project Admin manages)
│   ├── cmrc
│   ├── vntg
│   └── wlt
│
└── IDP Integration (groups synced from your Identity Provider)
    ├── ADMIN-{project-name}
    ├── READ-{project-name}
    └── WRITE-{project-name}
```

**Key design decisions:**

- Stages are defined **globally once** by Platform Admins; every project inherits them automatically.
- Each **product** maps to exactly one JFrog Project — following the JFrog-recommended "Team = Project" model.
- All user access is managed through **IDP groups**, never by assigning individual users directly inside JFrog.
- Project-level RBAC maps IDP groups to built-in JFrog roles (Developer, Contributor, Viewer, Project Admin).

---

## 2. Global Lifecycle Stages

Platform Admins define three global stages that represent the software delivery lifecycle. Every project created on the platform **inherits these stages automatically** — no per-project configuration is needed.

| Stage | Purpose | Who Can Write | Who Can Read |
|-------|---------|---------------|--------------|
| **DEV** | Active development; CI builds publish here | WRITE group, ADMIN group | READ, WRITE, ADMIN groups |
| **QA** | Promotion target after passing CI gates | ADMIN group (via pipeline promotion) | READ, WRITE, ADMIN groups |
| **PROD** | Certified, release-quality artifacts | ADMIN group (via pipeline promotion only) | READ, WRITE, ADMIN groups |

> **Best Practice:** Developers (WRITE group) have write access only to DEV. Promotions to QA and PROD are performed exclusively through automated pipeline actions authenticated via OIDC, never by a human directly uploading. This enforces the "least privilege" principle at each stage boundary.

### Stage Inheritance Model

```
Platform Level           Project Level
──────────────           ─────────────
DEV  (global)  ────────► cmrc/DEV
QA   (global)  ────────► cmrc/QA
PROD (global)  ────────► cmrc/PROD

               ────────► vntg/DEV
               ────────► vntg/QA
               ────────► vntg/PROD

               ────────► wlt/DEV
               ────────► wlt/QA
               ────────► wlt/PROD
```

No project-level stage configuration is required. Adding a new project automatically gives it access to the three global stages.

---

## 3. Project Structure — One Project Per Product

Each product line is provisioned as a dedicated JFrog Project. This ensures:

- **Resource isolation** — repositories, builds, and release bundles are scoped per product.
- **Storage quota accountability** — each project has its own quota, enabling cost tracking per product.
- **Delegated administration** — the product team's Project Admin group manages day-to-day operations without Platform Admin involvement.

### Project Naming Convention

| Field | Convention | Examples |
|-------|-----------|---------|
| **Project Name** | Product name (lowercase) | `cmrc`, `vntg`, `wlt` |
| **Project Key** | Same as project name (used as repository prefix) | `cmrc-`, `vntg-`, `wlt-` |

> **Note:** The Project Key is immutable after creation. Choose it carefully — it becomes the prefix for every repository inside the project (e.g., `cmrc-npm-dev-local`).

---

## 4. Identity Provider (IDP) Group Naming Convention

Three IDP groups are provisioned for **every project**. These groups are created in your IDP (e.g., Okta, Azure Entra ID, Active Directory) and synchronised into the JFrog Platform via SAML/SCIM or OIDC.

### Pattern

```
ADMIN-{project-name}
READ-{project-name}
WRITE-{project-name}
```

### Instantiated Groups

| Project | ADMIN Group | READ Group | WRITE Group |
|---------|-------------|------------|-------------|
| cmrc | `ADMIN-cmrc` | `READ-cmrc` | `WRITE-cmrc` |
| vntg | `ADMIN-vntg` | `READ-vntg` | `WRITE-vntg` |
| wlt | `ADMIN-wlt` | `READ-wlt` | `WRITE-wlt` |

> **Best Practice:** Never create ad-hoc groups in JFrog directly. All groups originate in the IDP and are pushed to JFrog through federation. This ensures deprovisioning (e.g., when an employee leaves) is handled in a single place.

---

## 5. User-to-Group Mapping (IDP)

User membership is managed entirely in the IDP. The following table shows the intended membership pattern. **All group membership changes must be made in the IDP**, not in the JFrog UI.

### Pattern

```
ADMIN-{project-name}
  └── User1

READ-{project-name}
  ├── User1
  ├── User2
  └── User3

WRITE-{project-name}
  ├── User1
  └── User2
```

### cmrc Example

```
ADMIN-cmrc
  └── User1

READ-cmrc
  ├── User1
  ├── User2
  └── User3

WRITE-cmrc
  ├── User1
  └── User2
```

### vntg Example

```
ADMIN-vntg
  └── User1

READ-vntg
  ├── User1
  ├── User2
  └── User3

WRITE-vntg
  ├── User1
  └── User2
```

### wlt Example

```
ADMIN-wlt
  └── User1

READ-wlt
  ├── User1
  ├── User2
  └── User3

WRITE-wlt
  ├── User1
  └── User2
```

> **Note on cumulative access:** A user who is a member of both `ADMIN-cmrc` and `READ-cmrc` receives the union of permissions from both roles. It is normal (and expected) for admins to also be in the READ group so they can resolve packages via the virtual repository URL.

---

## 6. Group-to-Role Mapping Inside JFrog Projects

Once IDP groups are synchronised to JFrog, they are assigned to **project-level roles** inside each project. Role assignment is performed by the Platform Admin at project creation time and may subsequently be maintained by the Project Admin.

### Role Mapping Pattern

| IDP Group | JFrog Project Role | Effective Permissions |
|-----------|-------------------|----------------------|
| `ADMIN-{project-name}` | **Project Admin** (built-in) | Full project management; can manage members, roles, and resources |
| `WRITE-{project-name}` | **Developer** (built-in) | Read + Write on DEV stage; Read-only on QA and PROD |
| `READ-{project-name}` | **Viewer** (built-in) | Read-only on all stages (DEV, QA, PROD) |

### Project-Level Group → Role Assignment

#### cmrc

```
Project: cmrc
├── Group: ADMIN-cmrc  →  Role: Project Admin
├── Group: WRITE-cmrc  →  Role: Developer
└── Group: READ-cmrc   →  Role: Viewer
```

#### vntg

```
Project: vntg
├── Group: ADMIN-vntg   →  Role: Project Admin
├── Group: WRITE-vntg   →  Role: Developer
└── Group: READ-vntg    →  Role: Viewer
```

#### wlt

```
Project: wlt
├── Group: ADMIN-wlt    →  Role: Project Admin
├── Group: WRITE-wlt    →  Role: Developer
└── Group: READ-wlt     →  Role: Viewer
```

### Stage-Level Access Matrix (effective permissions)

| Group | Role | DEV | QA | PROD |
|-------|------|-----|----|------|
| `ADMIN-{project}` | Project Admin | Read + Write | Read + Write | Read + Write |
| `WRITE-{project}` | Developer | Read + Write | Read only | Read only |
| `READ-{project}` | Viewer | Read only | Read only | Read only |

---

## 7. Project Admin Group

Each project has a designated **Project Admin group** at the platform level. This group name follows a separate, organisation-specific convention:

### Pattern

```
{product}-project-admin
```

### Examples

| Product | Project Admin Group |
|---------|-------------------|
| cmrc | `cmrc-project-admin` |
| vntg | `vntg-project-admin` |
| wlt | `wlt-project-admin` |

### Relationship to IDP Groups

The Project Admin group (`{product}-project-admin`) maps directly to the IDP group `ADMIN-{project-name}`. Both identifiers refer to the same set of users — the naming difference reflects the JFrog platform's internal convention versus the IDP group naming standard.

```
IDP Group            JFrog Project Admin Group
────────────         ─────────────────────────
ADMIN-cmrc  ──►  cmrc-project-admin
ADMIN-vntg   ──►  vntg-project-admin
ADMIN-wlt    ──►  wlt-project-admin
```

### Project Admin Responsibilities

The Project Admin can, **without Platform Admin involvement**:

- Add and remove project members (users and groups)
- Create, modify, and delete repositories within the project
- Assign and revoke project-level roles
- Manage storage quota alerts
- Configure OIDC identity mappings for CI pipelines

---

## 8. Repository Naming Convention

Repositories inside each project follow JFrog's recommended four-part naming structure:

```
{project-key}-{tech}-{maturity}-{locator}
```

| Part | Description | Examples |
|------|-------------|---------|
| `project-key` | The project key (product name) | `cmrc`, `vntg`, `wlt` |
| `tech` | Package type / technology | `npm`, `maven`, `docker`, `pypi` |
| `maturity` | Lifecycle stage | `dev`, `qa`, `prod` |
| `locator` | Repository type | `local`, `remote`, `virtual` |

### Examples for cmrc

| Repository Name | Type | Stage | Purpose |
|----------------|------|-------|---------|
| `cmrc-npm-dev-local` | Local | DEV | CI-published npm packages |
| `cmrc-npm-qa-local` | Local | QA | Promoted npm packages |
| `cmrc-npm-prod-local` | Local | PROD | Release npm packages |
| `cmrc-npm-dev-virtual` | Virtual | DEV | Aggregator (local + remote) for developers |
| `cmrc-docker-dev-local` | Local | DEV | CI-published Docker images |
| `cmrc-docker-prod-local` | Local | PROD | Release Docker images |

> **Best Practice:** Every project should have one Virtual repository per technology stack acting as a single URL for developers. Order the virtual repository's resolution list with the PROD local first, then QA, then DEV, then remote — this prioritises stable artifacts.

---

## 9. Full Reference — cmrc, vntg, wlt

This section provides the complete end-to-end mapping for each product.

---

### 9.1 cmrc

**Project Details**

| Attribute | Value |
|-----------|-------|
| Project Name | `cmrc` |
| Project Key | `cmrc` |
| Project Admin Group (JFrog) | `cmrc-project-admin` |
| Storage Quota | Set per platform quota policy |

**IDP Groups**

| Group Name | Members |
|-----------|---------|
| `ADMIN-cmrc` | User1 |
| `WRITE-cmrc` | User1, User2 |
| `READ-cmrc` | User1, User2, User3 |

**JFrog Role Assignments**

| IDP Group | JFrog Role |
|-----------|-----------|
| `ADMIN-cmrc` | Project Admin |
| `WRITE-cmrc` | Developer |
| `READ-cmrc` | Viewer |

**Stage Access**

| Group | DEV | QA | PROD |
|-------|-----|----|------|
| `ADMIN-cmrc` | R/W | R/W | R/W |
| `WRITE-cmrc` | R/W | R | R |
| `READ-cmrc` | R | R | R |

---

### 9.2 vntg

**Project Details**

| Attribute | Value |
|-----------|-------|
| Project Name | `vntg` |
| Project Key | `vntg` |
| Project Admin Group (JFrog) | `vntg-project-admin` |

**IDP Groups**

| Group Name | Members |
|-----------|---------|
| `ADMIN-vntg` | User1 |
| `WRITE-vntg` | User1, User2 |
| `READ-vntg` | User1, User2, User3 |

**JFrog Role Assignments**

| IDP Group | JFrog Role |
|-----------|-----------|
| `ADMIN-vntg` | Project Admin |
| `WRITE-vntg` | Developer |
| `READ-vntg` | Viewer |

**Stage Access**

| Group | DEV | QA | PROD |
|-------|-----|----|------|
| `ADMIN-vntg` | R/W | R/W | R/W |
| `WRITE-vntg` | R/W | R | R |
| `READ-vntg` | R | R | R |

---

### 9.3 wlt

**Project Details**

| Attribute | Value |
|-----------|-------|
| Project Name | `wlt` |
| Project Key | `wlt` |
| Project Admin Group (JFrog) | `wlt-project-admin` |

**IDP Groups**

| Group Name | Members |
|-----------|---------|
| `ADMIN-wlt` | User1 |
| `WRITE-wlt` | User1, User2 |
| `READ-wlt` | User1, User2, User3 |

**JFrog Role Assignments**

| IDP Group | JFrog Role |
|-----------|-----------|
| `ADMIN-wlt` | Project Admin |
| `WRITE-wlt` | Developer |
| `READ-wlt` | Viewer |

**Stage Access**

| Group | DEV | QA | PROD |
|-------|-----|----|------|
| `ADMIN-wlt` | R/W | R/W | R/W |
| `WRITE-wlt` | R/W | R | R |
| `READ-wlt` | R | R | R |

---

## 10. Onboarding a New Product Team

When a new product (e.g., `payments`) needs to be added to the platform, follow this checklist in order:

### Step 1 — Platform Admin: Create the Project

- [ ] Create JFrog Project with name `payments` and project key `payments`
- [ ] Set storage quota per organisational policy
- [ ] Verify the project inherits the three global stages (DEV, QA, PROD) automatically

### Step 2 — IDP Team: Provision Groups

- [ ] Create IDP group `ADMIN-payments` and add the designated project admin user(s)
- [ ] Create IDP group `WRITE-payments` and add developer users
- [ ] Create IDP group `READ-payments` and add all stakeholders who need read access
- [ ] Confirm IDP group sync is enabled and groups appear in JFrog Administration > Groups

### Step 3 — Platform Admin: Assign Groups to Project Roles

- [ ] Inside the `payments` project → Members → Add group `ADMIN-payments` → Role: **Project Admin**
- [ ] Inside the `payments` project → Members → Add group `WRITE-payments` → Role: **Developer**
- [ ] Inside the `payments` project → Members → Add group `READ-payments` → Role: **Viewer**

### Step 4 — Project Admin: Create Repositories

- [ ] Create local repositories per technology and stage, following the naming convention:
  `payments-{tech}-{dev|qa|prod}-local`
- [ ] Create one virtual repository per technology as the developer-facing aggregator:
  `payments-{tech}-dev-virtual`
- [ ] Map local repositories to their respective stages (DEV, QA, PROD) in project settings

### Step 5 — Platform Admin: Configure CI OIDC (Recommended)

- [ ] Create an OIDC configuration for the product's CI system (GitHub Actions, GitLab CI, etc.)
- [ ] Create identity mappings that link OIDC claims to the `Developer` role in the `payments` project
- [ ] Remove any static access tokens previously used by CI pipelines

---

## 11. Quick Reference Table

| Concept | Pattern | cmrc Example |
|---------|---------|-----------------|
| JFrog Project Name | `{product}` | `cmrc` |
| JFrog Project Key | `{product}` | `cmrc` |
| Project Admin Group (JFrog) | `{product}-project-admin` | `cmrc-project-admin` |
| IDP Admin Group | `ADMIN-{project-name}` | `ADMIN-cmrc` |
| IDP Write Group | `WRITE-{project-name}` | `WRITE-cmrc` |
| IDP Read Group | `READ-{project-name}` | `READ-cmrc` |
| ADMIN group → JFrog role | `ADMIN-{x}` → Project Admin | `ADMIN-cmrc` → Project Admin |
| WRITE group → JFrog role | `WRITE-{x}` → Developer | `WRITE-cmrc` → Developer |
| READ group → JFrog role | `READ-{x}` → Viewer | `READ-cmrc` → Viewer |
| Repository naming | `{key}-{tech}-{stage}-{type}` | `cmrc-npm-dev-local` |
| Global stages | DEV, QA, PROD | Inherited by all projects |

---

## References

- [JFrog Projects — Get Started](https://docs.jfrog.com/projects/docs/projects)
- [Projects Best Practices](https://docs.jfrog.com/projects/docs/projects-best-practices)
- [Projects Setup Best Practices](https://docs.jfrog.com/projects/docs/projects-setup-best-practices)
- [Manage Project Roles and Members](https://docs.jfrog.com/projects/docs/manage-project-roles-and-members)
- [Project Admin Role](https://docs.jfrog.com/projects/docs/project-admin-role)
- [Stages & Lifecycle](https://docs.jfrog.com/administration/docs/stages-lifecycle)
- [OpenID Connect Integration](https://docs.jfrog.com/administration/docs/openid-connect-integration)
- [Repository Naming Best Practices](https://jfrog.com/whitepaper/best-practices-structuring-naming-artifactory-repositories/)
