#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# run.sh — Layered Terraform runner for the JFrog Platform
#
# Layout (set up by the scale refactor):
#   platform/                ← state #1, slow-changing (projects, groups, stages)
#   projects/<key>/          ← one state per project, parallel-applicable
#
# Order:
#   1. platform/             (sequential, must succeed before any project layer)
#   2. projects/*/           (parallel)
#
# Usage:
#   ./run.sh                  prompts for credentials on first run, applies all layers
#   ./run.sh --auto           non-interactive (CI)
#   ./run.sh --plan-only      plan every layer, apply nothing
#   ./run.sh --platform-only  apply platform layer only
#   ./run.sh --project <key>  apply one project layer only
# ---------------------------------------------------------------------------
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
step()    { echo -e "\n${BOLD}${CYAN}==> $*${NC}"; }

# ── Args ────────────────────────────────────────────────────────────────────
AUTO_APPROVE=false
PLAN_ONLY=false
PLATFORM_ONLY=false
SINGLE_PROJECT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --auto)          AUTO_APPROVE=true ;;
    --plan-only)     PLAN_ONLY=true ;;
    --platform-only) PLATFORM_ONLY=true ;;
    --project)       SINGLE_PROJECT="$2"; shift ;;
    --help|-h)
      echo "Usage: ./run.sh [--auto] [--plan-only] [--platform-only] [--project <key>]"
      exit 0 ;;
    *) error "Unknown argument: $1"; exit 1 ;;
  esac
  shift
done

# ── Lock ────────────────────────────────────────────────────────────────────
LOCKFILE="/tmp/jfrog_tf_run.lock"
if [ -f "$LOCKFILE" ]; then
  error "Another run.sh is running (lock: $LOCKFILE). Remove if stale: rm $LOCKFILE"
  exit 1
fi
touch "$LOCKFILE"
trap 'rm -f "$LOCKFILE"' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
info "Working directory: $SCRIPT_DIR"

# ── Prereqs ─────────────────────────────────────────────────────────────────
step "Checking prerequisites"
for cmd in terraform curl python3 jq; do
  if ! command -v "$cmd" &>/dev/null; then
    error "$cmd is required."
    [ "$cmd" = "jq" ] && error "Install: brew install jq"
    exit 1
  fi
done
success "All prerequisites found."

# ── Credentials — set TF_VAR_* so every layer inherits them ────────────────
step "Loading credentials"
if [ -f "terraform.tfvars" ]; then
  export TF_VAR_jfrog_url=$(grep -E '^jfrog_url' terraform.tfvars | awk -F'"' '{print $2}')
  export TF_VAR_jfrog_access_token=$(grep -E '^jfrog_access_token' terraform.tfvars | awk -F'"' '{print $2}')
  success "Loaded from terraform.tfvars"
elif [ -n "${TF_VAR_jfrog_url:-}" ] && [ -n "${TF_VAR_jfrog_access_token:-}" ]; then
  success "Loaded from environment"
else
  if [ "$AUTO_APPROVE" = "true" ]; then
    error "No credentials. Either create terraform.tfvars or set TF_VAR_jfrog_url / TF_VAR_jfrog_access_token."
    exit 1
  fi
  echo ""
  read -rp "  Enter JFrog Platform URL (no trailing slash): " URL
  read -rsp "  Enter access token (hidden): " TOK; echo ""
  URL="${URL%/}"
  export TF_VAR_jfrog_url="$URL"
  export TF_VAR_jfrog_access_token="$TOK"
  cat > terraform.tfvars <<EOF
jfrog_url          = "$URL"
jfrog_access_token = "$TOK"
EOF
  success "Credentials saved to terraform.tfvars"
fi

# ── Backend auth — Artifactory HTTP backend uses basic-auth.
# JFrog requires the username portion match the token's subject claim, so
# we decode the JWT and extract it.
JF_USERNAME=$(echo "$TF_VAR_jfrog_access_token" | python3 -c '
import sys, base64, json
tok = sys.stdin.read().strip()
payload = tok.split(".")[1]
payload += "=" * (-len(payload) % 4)
data = json.loads(base64.urlsafe_b64decode(payload))
print(data.get("sub", "").rsplit("/", 1)[-1])
' 2>/dev/null)

if [ -z "$JF_USERNAME" ]; then
  error "Could not decode username from access token. Token may be malformed."
  exit 1
fi
export TF_HTTP_USERNAME="$JF_USERNAME"
export TF_HTTP_PASSWORD="$TF_VAR_jfrog_access_token"
info "Backend auth: TF_HTTP_USERNAME=$JF_USERNAME"

# ── Discover project layers from filesystem ────────────────────────────────
discover_projects() {
  find projects -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort
}

# ── Helpers ────────────────────────────────────────────────────────────────
apply_layer() {
  local layer_dir="$1"
  local label="$2"

  step "Layer: $label  ($layer_dir)"

  pushd "$layer_dir" >/dev/null

  if [ ! -d ".terraform" ]; then
    info "  Initialising..."
    terraform init -input=false -no-color | tail -3
  fi

  # Per-layer parallelism is capped to avoid overrunning JFrog's GRPC pool.
  # JFrog SaaS instances start returning 429 "GRPC Server thread has reached
  # its limits" around ~10 concurrent writes. Default terraform parallelism
  # is 10 per layer, and we may run several layers concurrently, so this
  # cap keeps total concurrent JFrog calls reasonable.
  local PAR="${TF_PARALLELISM:-4}"

  if [ "$PLAN_ONLY" = "true" ]; then
    terraform plan -no-color -parallelism="$PAR" | tail -20
  else
    terraform apply -auto-approve -no-color -parallelism="$PAR" 2>&1 | tail -10
  fi

  popd >/dev/null
  success "$label complete."
}

# Apply order: platform -> projects/* (parallel) -> curation.
# Curation is last because it has no dependency on platform/project resources
# and its failure should not block the actual provisioning (project + repos).

# ── Phase 1: Platform layer (control plane) ────────────────────────────────
if [ -z "$SINGLE_PROJECT" ]; then
  apply_layer "platform" "platform"
fi

if [ "$PLATFORM_ONLY" = "true" ]; then
  success "Platform-only run complete."
  exit 0
fi

# ── Phase 2: Project layers (parallel) ─────────────────────────────────────
# Portable replacement for `mapfile` (bash 4+ builtin, not present in macOS bash 3.2)
projects_to_apply=()
if [ -n "$SINGLE_PROJECT" ]; then
  projects_to_apply+=("$SINGLE_PROJECT")
else
  while IFS= read -r proj; do
    [ -n "$proj" ] && projects_to_apply+=("$proj")
  done < <(discover_projects)
fi

step "Applying ${#projects_to_apply[@]} project layer(s) in parallel"

pids=()
for proj in "${projects_to_apply[@]}"; do
  if [ ! -d "projects/$proj" ]; then
    error "  projects/$proj not found, skipping."
    continue
  fi
  (apply_layer "projects/$proj" "project:$proj" 2>&1 | sed "s/^/[$proj] /") &
  pids+=($!)
done

# Wait for all parallel project layers
fail_count=0
for pid in "${pids[@]}"; do
  if ! wait "$pid"; then
    fail_count=$((fail_count + 1))
  fi
done

if [ "$fail_count" -gt 0 ]; then
  error "$fail_count project layer(s) failed."
  exit 1
fi

# ── Phase 3: Curation layer (LAST) ─────────────────────────────────────────
# Curation policies are platform-wide but independent of project/repo
# lifecycle. Running last means a curation API hiccup never blocks the
# actual provisioning. If you only want to apply curation (no platform/
# projects), cd terraform/curation && terraform apply directly.
if [ -z "$SINGLE_PROJECT" ] && [ -d "curation" ]; then
  apply_layer "curation" "curation"
fi

success "All layers complete."
