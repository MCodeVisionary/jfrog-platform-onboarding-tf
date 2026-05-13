#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# cleanup.sh — Layered Terraform destroyer for the JFrog Platform
#
# Destroy order (strict, to avoid JFrog's "Project containing resources" bug):
#
#   Phase 1 — projects/*/         (parallel)
#               └─ destroys all artifactory_* repos (no project state)
#
#   Phase 2 — platform/           (sequential, phased internally via -target)
#               ├─ 2a project_group.this              (role bindings)
#               ├─ 2b project.this                    (the projects)
#               ├─ 2c null_resource.{global,project}_stages
#               └─ 2d platform_group.*                (group shells)
#
# Phase 2 uses targeted destroys with retries because JFrog's internal
# resource-count cache can refuse a project delete even after every API
# query says the project is empty.
#
# Usage:
#   ./cleanup.sh                     interactive
#   ./cleanup.sh --auto              non-interactive
#   ./cleanup.sh --state-only        wipe local state/cache only, don't touch JFrog
#   ./cleanup.sh --project <key>     destroy one project's layer (leaves platform alone)
#   ./cleanup.sh --platform-only     destroy platform layer only (assumes projects already empty)
# ---------------------------------------------------------------------------
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
step()    { echo -e "\n${BOLD}${CYAN}==> $*${NC}"; }

# ── Args ───────────────────────────────────────────────────────────────────
AUTO_APPROVE=false
STATE_ONLY=false
PLATFORM_ONLY=false
SINGLE_PROJECT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --auto)          AUTO_APPROVE=true ;;
    --state-only)    STATE_ONLY=true ;;
    --platform-only) PLATFORM_ONLY=true ;;
    --project)       SINGLE_PROJECT="$2"; shift ;;
    --help|-h)
      echo "Usage: ./cleanup.sh [--auto] [--state-only] [--platform-only] [--project <key>]"
      exit 0 ;;
    *) error "Unknown argument: $1"; exit 1 ;;
  esac
  shift
done

# ── Lock ───────────────────────────────────────────────────────────────────
LOCKFILE="/tmp/jfrog_tf_cleanup.lock"
[ -f "$LOCKFILE" ] && { error "Another cleanup is running. Remove if stale: rm $LOCKFILE"; exit 1; }
touch "$LOCKFILE"
trap 'rm -f "$LOCKFILE"' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
info "Working directory: $SCRIPT_DIR"

# ── Banner + confirm ───────────────────────────────────────────────────────
echo ""
echo -e "${RED}${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}${BOLD}║           JFROG PLATFORM CLEANUP                         ║${NC}"
echo -e "${RED}${BOLD}║                                                          ║${NC}"
if [ "$STATE_ONLY" = "true" ]; then
echo -e "${RED}${BOLD}║  --state-only: wipes LOCAL state only, JFrog untouched.  ║${NC}"
elif [ -n "$SINGLE_PROJECT" ]; then
echo -e "${RED}${BOLD}║  Destroying ONE project layer: $SINGLE_PROJECT                       ║${NC}"
elif [ "$PLATFORM_ONLY" = "true" ]; then
echo -e "${RED}${BOLD}║  Destroying platform layer only.                         ║${NC}"
else
echo -e "${RED}${BOLD}║  Destroying ALL JFrog projects, repos, groups, stages.   ║${NC}"
fi
echo -e "${RED}${BOLD}║  This action cannot be undone.                           ║${NC}"
echo -e "${RED}${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

if [ "$AUTO_APPROVE" = "false" ] && [ "$STATE_ONLY" = "false" ]; then
  read -rp "Type 'destroy' to confirm: " CONFIRM
  [ "$CONFIRM" = "destroy" ] || { info "Cancelled."; exit 0; }
fi

# ── State-only mode ────────────────────────────────────────────────────────
if [ "$STATE_ONLY" = "true" ]; then
  step "Removing local Terraform state/cache from all layers"
  find platform projects -name "terraform.tfstate*" -type f -delete 2>/dev/null || true
  find platform projects -name ".terraform.lock.hcl" -type f -delete 2>/dev/null || true
  find platform projects -name "tfplan" -type f -delete 2>/dev/null || true
  find platform projects -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
  success "Local state wiped. JFrog instance untouched."
  exit 0
fi

# ── Prereqs ────────────────────────────────────────────────────────────────
for cmd in terraform curl; do
  command -v "$cmd" >/dev/null || { error "$cmd is required."; exit 1; }
done

# ── Credentials ────────────────────────────────────────────────────────────
if [ -f "terraform.tfvars" ]; then
  TF_VAR_jfrog_url=$(grep -E '^jfrog_url' terraform.tfvars | awk -F'"' '{print $2}')
  TF_VAR_jfrog_access_token=$(grep -E '^jfrog_access_token' terraform.tfvars | awk -F'"' '{print $2}')
  export TF_VAR_jfrog_url TF_VAR_jfrog_access_token
elif [ -z "${TF_VAR_jfrog_url:-}" ] || [ -z "${TF_VAR_jfrog_access_token:-}" ]; then
  error "No credentials. Either create terraform.tfvars or set TF_VAR_jfrog_url / TF_VAR_jfrog_access_token."
  exit 1
fi

# ── Helpers ────────────────────────────────────────────────────────────────

# Run `terraform destroy` with optional -target args. Retries on the
# specific "Project containing resources" 400 because JFrog's count cache
# sometimes lags the actual repo deletions by a few seconds.
destroy_with_retry() {
  local label="$1"; shift
  local max_attempts=4
  local attempt=1

  while [ $attempt -le $max_attempts ]; do
    if terraform destroy -auto-approve -no-color "$@" 2>&1 | tee /tmp/tf_destroy.out | tail -20; then
      return 0
    fi

    if grep -q "Project containing resources can't be removed" /tmp/tf_destroy.out; then
      warn "  $label: JFrog reports project still has resources (attempt $attempt/$max_attempts)."
      warn "  JFrog's project-resource-count cache hasn't refreshed yet. Sleeping 30s and retrying."
      attempt=$((attempt + 1))
      sleep 30
      continue
    fi

    return 1
  done

  error "$label: exhausted retries."
  return 1
}

layer_has_state() {
  local layer_dir="$1"
  [ -f "$layer_dir/terraform.tfstate" ] && [ -s "$layer_dir/terraform.tfstate" ]
}

ensure_init() {
  local layer_dir="$1"
  [ -d "$layer_dir/.terraform" ] || (cd "$layer_dir" && terraform init -input=false -no-color | tail -3)
}

# Destroy one project layer (everything in projects/<key>/)
destroy_project_layer() {
  local proj_dir="$1"
  local proj=$(basename "$proj_dir")

  step "Destroying project layer: $proj"
  if ! layer_has_state "$proj_dir"; then
    info "  No state — skipping."
    return 0
  fi
  ensure_init "$proj_dir"
  (cd "$proj_dir" && destroy_with_retry "project:$proj")
  success "Project layer $proj destroyed."
}

# Destroy the platform layer in phases.
destroy_platform_layer() {
  local pdir="platform"

  if ! layer_has_state "$pdir"; then
    info "  Platform layer has no state — skipping."
    return 0
  fi
  ensure_init "$pdir"

  step "Phase 2a — project_group bindings"
  (cd "$pdir" && destroy_with_retry "project_group.this" -target='module.platform.project_group.this')

  step "Phase 2b — projects"
  (cd "$pdir" && destroy_with_retry "project.this" -target='module.platform.project.this')

  step "Phase 2c — stages (global + project-specific)"
  (cd "$pdir" && destroy_with_retry "null_resource stages" \
    -target='module.platform.null_resource.global_stages' \
    -target='module.platform.null_resource.project_stages')

  step "Phase 2d — groups (per-project + platform-wide)"
  (cd "$pdir" && destroy_with_retry "platform groups" \
    -target='module.platform.platform_group.admin' \
    -target='module.platform.platform_group.write' \
    -target='module.platform.platform_group.read' \
    -target='module.platform.platform_group.security_admin' \
    -target='module.platform.platform_group.curation_approver')

  step "Phase 2e — final sweep (anything missed)"
  (cd "$pdir" && destroy_with_retry "final sweep")
}

# ── --project <key>: just one project, don't touch platform ───────────────
if [ -n "$SINGLE_PROJECT" ]; then
  if [ ! -d "projects/$SINGLE_PROJECT" ]; then
    error "projects/$SINGLE_PROJECT not found."
    exit 1
  fi
  destroy_project_layer "projects/$SINGLE_PROJECT"
  echo ""
  success "Cleanup complete (single project: $SINGLE_PROJECT)."
  exit 0
fi

# ── --platform-only: skip phase 1 ─────────────────────────────────────────
if [ "$PLATFORM_ONLY" = "true" ]; then
  destroy_platform_layer
  echo ""
  success "Cleanup complete (platform only)."
  exit 0
fi

# ── Phase 1: project layers (parallel) ────────────────────────────────────
step "Phase 1: Destroying project layers (parallel)"
pids=()
for proj_dir in projects/*/; do
  [ -d "$proj_dir" ] || continue
  proj=$(basename "$proj_dir")
  (destroy_project_layer "$proj_dir" 2>&1 | sed "s/^/[$proj] /") &
  pids+=($!)
done

phase1_fail=0
for pid in "${pids[@]}"; do
  wait "$pid" || phase1_fail=$((phase1_fail + 1))
done

if [ $phase1_fail -gt 0 ]; then
  error "$phase1_fail project layer(s) failed. Not proceeding to platform destroy."
  error "Resolve project-layer failures and re-run cleanup."
  exit 1
fi
success "Phase 1 complete."

# ── Phase 2: platform layer ───────────────────────────────────────────────
destroy_platform_layer
success "Phase 2 complete."

# ── Verification ──────────────────────────────────────────────────────────
step "Verifying JFrog state"
URL="$TF_VAR_jfrog_url"
TOK="$TF_VAR_jfrog_access_token"
remaining=0
for key in $(jq -r '.projects | to_entries[] | .value.key' platform/projects.json 2>/dev/null); do
  http=$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $TOK" "$URL/access/api/v1/projects/$key")
  if [ "$http" = "404" ]; then
    info "  project $key: gone (404)"
  else
    warn "  project $key: still present (HTTP $http)"
    remaining=$((remaining + 1))
  fi
done

if [ "$remaining" -gt 0 ]; then
  warn "$remaining project(s) still present in JFrog. Likely a cache lag — re-run cleanup in a few minutes if it persists."
fi

# ── Local cleanup ─────────────────────────────────────────────────────────
if [ "$AUTO_APPROVE" = "true" ]; then
  step "Removing local state files"
  find platform projects -name "terraform.tfstate*" -type f -delete 2>/dev/null || true
  find platform projects -name "tfplan" -type f -delete 2>/dev/null || true
  find platform projects -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
  find platform projects -name ".terraform.lock.hcl" -type f -delete 2>/dev/null || true
  success "Local state wiped."
fi

echo ""
success "Cleanup complete. projects.json, repos.json, and .tf files preserved."
