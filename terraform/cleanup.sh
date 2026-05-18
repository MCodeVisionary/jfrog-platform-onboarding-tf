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
echo -e "${RED}${BOLD}║  --state-only: wipes LOCAL caches only, JFrog untouched. ║${NC}"
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
# State lives REMOTELY in Artifactory's terraform-state-local repo, so there
# is no local tfstate file to delete. We only wipe the local provider/module
# cache (.terraform/) and saved plans (tfplan). .terraform.lock.hcl is
# preserved on purpose — it's source-controlled and pins provider versions.
if [ "$STATE_ONLY" = "true" ]; then
  step "Removing local Terraform caches (state lives remotely, untouched)"
  find platform projects -name "tfplan" -type f -delete 2>/dev/null || true
  find platform projects -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
  # Belt-and-braces in case stray local state files exist from older runs
  find platform projects -name "terraform.tfstate" -type f -delete 2>/dev/null || true
  find platform projects -name "terraform.tfstate.backup" -type f -delete 2>/dev/null || true
  success "Local caches wiped. JFrog (incl. remote state in terraform-state-local) untouched."
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

# Backend auth (Artifactory HTTP backend) — username from JWT sub claim
JF_USERNAME=$(echo "$TF_VAR_jfrog_access_token" | python3 -c '
import sys, base64, json
tok = sys.stdin.read().strip()
payload = tok.split(".")[1]
payload += "=" * (-len(payload) % 4)
data = json.loads(base64.urlsafe_b64decode(payload))
print(data.get("sub", "").rsplit("/", 1)[-1])
' 2>/dev/null)

if [ -n "$JF_USERNAME" ]; then
  export TF_HTTP_USERNAME="$JF_USERNAME"
  export TF_HTTP_PASSWORD="$TF_VAR_jfrog_access_token"
fi

# ── Helpers ────────────────────────────────────────────────────────────────

# Per-layer terraform parallelism cap. JFrog SaaS rate-limits writes around
# 10 concurrent calls ("HTTP 429: GRPC Server thread has reached its limits").
# Destroy is just as API-heavy as apply (each repo removal makes a
# project-disassociation call), so we cap the same way as run.sh.
TF_PARALLELISM="${TF_PARALLELISM:-4}"

# Run `terraform destroy` with optional -target args. Retries on the
# specific "Project containing resources" 400 because JFrog's count cache
# sometimes lags the actual repo deletions by a few seconds, AND on the
# 429 GRPC pool exhaustion because that's transient.
destroy_with_retry() {
  local label="$1"; shift
  local max_attempts=4
  local attempt=1

  while [ $attempt -le $max_attempts ]; do
    if terraform destroy -auto-approve -no-color -parallelism="$TF_PARALLELISM" "$@" 2>&1 | tee /tmp/tf_destroy.out | tail -20; then
      return 0
    fi

    if grep -q "Project containing resources can't be removed" /tmp/tf_destroy.out; then
      warn "  $label: JFrog reports project still has resources (attempt $attempt/$max_attempts)."
      warn "  JFrog's project-resource-count cache hasn't refreshed yet. Sleeping 30s and retrying."
      attempt=$((attempt + 1))
      sleep 30
      continue
    fi

    if grep -q "GRPC Server thread has reached its limits" /tmp/tf_destroy.out; then
      warn "  $label: JFrog rate-limited (attempt $attempt/$max_attempts)."
      warn "  Sleeping 20s and retrying — terraform's partial-apply behaviour will pick up where it left off."
      attempt=$((attempt + 1))
      sleep 20
      continue
    fi

    return 1
  done

  error "$label: exhausted retries."
  return 1
}

layer_has_state() {
  local layer_dir="$1"
  # State is remote (Artifactory) — there's no local file to stat. After init,
  # `terraform state list` returns 0 with at least one line if the remote state
  # has resources. We treat any output as "has state".
  if [ ! -d "$layer_dir/.terraform" ]; then
    (cd "$layer_dir" && terraform init -input=false -no-color >/dev/null 2>&1) || return 1
  fi
  local n
  n=$(cd "$layer_dir" && terraform state list 2>/dev/null | wc -l | tr -d ' ')
  [ "${n:-0}" -gt 0 ]
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
# Order (per project policy):
#   repos → project → roles → groups → members → stages
#
# How each maps in this terraform:
#   repos     = projects/<key>/ layers  (Phase 1 above, before this function runs)
#   project   = module.platform.project.this
#               Targeting it cascades (via depends_on) to anything that
#               depends on it: project_group bindings AND
#               null_resource.project_stages. So "destroy project" actually
#               removes the project + its role-bindings + its project-stages
#               in one step, in the correct internal order.
#   roles     = module.platform.project_group.this — covered by the cascade
#   groups    = module.platform.platform_group.{admin,write,read,security_admin,curation_approver}
#   members   = (none — user resources are not currently managed by terraform)
#   stages    = module.platform.null_resource.global_stages
#               (project_stages was already destroyed by the project cascade)
destroy_platform_layer() {
  local pdir="platform"

  if ! layer_has_state "$pdir"; then
    info "  Platform layer has no state — skipping."
    return 0
  fi
  ensure_init "$pdir"

  step "Phase 2a — projects (cascades to role bindings + project stages)"
  (cd "$pdir" && destroy_with_retry "project.this" -target='module.platform.project.this')

  step "Phase 2b — roles (any leftover role bindings not removed by cascade)"
  (cd "$pdir" && destroy_with_retry "project_group.this" -target='module.platform.project_group.this')

  step "Phase 2c — groups (per-project + platform-wide)"
  (cd "$pdir" && destroy_with_retry "platform groups" \
    -target='module.platform.platform_group.admin' \
    -target='module.platform.platform_group.write' \
    -target='module.platform.platform_group.read' \
    -target='module.platform.platform_group.security_admin' \
    -target='module.platform.platform_group.curation_approver')

  step "Phase 2d — members (no-op: users not managed by terraform yet)"
  info "  Skipped — no platform_user / project_user resources in this codebase."

  # ── Phase 2e — global stages ────────────────────────────────────────────
  # null_resource.global_stages only has a *create*-time provisioner that
  # POSTs to /access/api/v1/environments. There is no destroy provisioner,
  # so `terraform destroy` removes the null_resource from state without
  # telling JFrog to delete the env. We do that explicitly here.
  #
  # Note: if a stage name (e.g. PROD) is used by other repos outside this
  # terraform's scope, JFrog will refuse to delete it. That's fine — we
  # log and continue.
  step "Phase 2e — global stages (destroy + explicit JFrog API delete)"
  (cd "$pdir" && destroy_with_retry "null_resource.global_stages" \
    -target='module.platform.null_resource.global_stages')

  # JFrog protects some built-in stages: DEV and PROD return 403 Forbidden
  # on DELETE. Custom stages we add (e.g. QA, STG, UAT) can be deleted.
  # We try all configured global_stage_names and treat 403 as expected.
  info "  Deleting global stages via JFrog Access API:"
  for stage in DEV QA STG PROD; do
    http=$(curl -s -o /tmp/stage_del.json -w "%{http_code}" \
      -X DELETE \
      -H "Authorization: Bearer $TF_VAR_jfrog_access_token" \
      "$TF_VAR_jfrog_url/access/api/v1/environments/$stage")
    case "$http" in
      204|200) info "    $stage: deleted ($http)" ;;
      404)     info "    $stage: already gone (404)" ;;
      403)     info "    $stage: protected built-in stage — kept (403, expected)" ;;
      *)
        msg=$(python3 -c "import json; print(json.load(open('/tmp/stage_del.json')).get('errors',[{}])[0].get('message',''))" 2>/dev/null || echo "")
        warn "    $stage: HTTP $http — $msg"
        ;;
    esac
  done

  step "Phase 2f — final sweep (anything missed)"
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

# Destroy order is the reverse of apply order in run.sh:
#   apply:   platform -> projects/* -> curation
#   destroy: curation -> projects/* -> platform

# ── Phase 1: curation layer ───────────────────────────────────────────────
if [ -d "curation" ]; then
  step "Phase 1: Destroying curation layer"
  if layer_has_state "curation"; then
    ensure_init "curation"
    (cd curation && destroy_with_retry "curation")
    success "Curation layer destroyed."
  else
    info "  Curation layer has no state — skipping."
  fi
fi

# ── Phase 2: project layers (parallel) ────────────────────────────────────
step "Phase 2: Destroying project layers (parallel)"
pids=()
for proj_dir in projects/*/; do
  [ -d "$proj_dir" ] || continue
  proj=$(basename "$proj_dir")
  (destroy_project_layer "$proj_dir" 2>&1 | sed "s/^/[$proj] /") &
  pids+=($!)
done

phase2_fail=0
for pid in "${pids[@]}"; do
  wait "$pid" || phase2_fail=$((phase2_fail + 1))
done

if [ $phase2_fail -gt 0 ]; then
  error "$phase2_fail project layer(s) failed. Not proceeding to platform destroy."
  error "Resolve project-layer failures and re-run cleanup."
  exit 1
fi
success "Phase 2 complete."

# ── Phase 3: platform layer ───────────────────────────────────────────────
destroy_platform_layer
success "Phase 3 complete."

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
# State lives in Artifactory and is emptied by terraform destroy above; we
# only wipe the local provider/module cache. .terraform.lock.hcl is
# source-controlled, so we leave it alone.
if [ "$AUTO_APPROVE" = "true" ]; then
  step "Removing local provider/module cache"
  find platform projects -name "tfplan" -type f -delete 2>/dev/null || true
  find platform projects -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
  # Belt-and-braces if any stray local state files exist
  find platform projects -name "terraform.tfstate" -type f -delete 2>/dev/null || true
  find platform projects -name "terraform.tfstate.backup" -type f -delete 2>/dev/null || true
  success "Local caches wiped (.terraform.lock.hcl preserved — source-controlled)."
fi

echo ""
success "Cleanup complete. projects.json, repos.json, and .tf files preserved."
