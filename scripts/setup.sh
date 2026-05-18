#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# setup.sh — Fork helper: swap the example JFrog host for your own.
#
# This public repo ships with a CONCRETE working example using the JFrog
# host `mcodevisionaryorg.jfrog.io`. It's a real, working configuration —
# easier to read than placeholders, but obviously tied to one tenant.
#
# If you fork this repo for a different JFrog tenant, run this script once
# to substitute the example host for your own:
#
#   ./scripts/setup.sh <your-jfrog-host>
#
# Examples:
#   ./scripts/setup.sh acme.jfrog.io
#   ./scripts/setup.sh jfrog.acme-internal.com
#   ./scripts/setup.sh acme.jfrog.io:8082
#
# What it changes:
#   - terraform/platform/backend.tf
#   - terraform/curation/backend.tf
#   - terraform/projects/<key>/backend.tf  (every project layer)
#   - .github/scripts/intake_new_project.py  (TF_BACKEND template the intake
#     bot stamps into new project scaffolds)
#
# What it does NOT change (manual edits for a fork):
#   - .github/CODEOWNERS — team handles (@MCodeVisionary/... → @<your-org>/...)
#   - source = "git::https://github.com/MCodeVisionary/..." in
#     terraform/{platform,curation,projects/*}/main.tf — point at your fork
#   - terraform/platform/projects.json — your projects, not cmrc/vntg/wlt
#   - terraform/projects/<key>/repos.json — your repo definitions
#   - terraform/curation/curation_policies.json — your policies
#
# Idempotent: safe to re-run with the same host. To switch hosts later, just
# call it again with the new value (script substitutes whatever the current
# host is for the new one).
# ---------------------------------------------------------------------------
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'

# The host currently in the codebase. Update this if the example is ever
# rebased on a different reference host.
DEFAULT_EXAMPLE_HOST="mcodevisionaryorg.jfrog.io"

usage() {
  cat <<EOF
Usage: $0 <your-jfrog-host>

Examples:
  $0 acme.jfrog.io
  $0 jfrog.acme-internal.com
  $0 acme.jfrog.io:8082

The host must NOT include the https:// scheme or a trailing slash.
EOF
  exit 1
}

if [ $# -ne 1 ] || [ -z "$1" ]; then
  echo -e "${RED}Error: missing JFrog host argument.${NC}"
  usage
fi

NEW_HOST="$1"

case "$NEW_HOST" in
  https://*|http://*)
    echo -e "${RED}Error: do not include the scheme (https://).${NC} Pass just '${NEW_HOST#*://}'."
    exit 1
    ;;
  */*|*\\*)
    echo -e "${RED}Error: '$NEW_HOST' does not look like a hostname (no slashes).${NC}"
    exit 1
    ;;
esac

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# Detect the current host: prefer whatever is actually in the backend files
# (in case someone already substituted), otherwise use DEFAULT_EXAMPLE_HOST.
CURRENT_HOST=$(grep -hoE '[a-z0-9.-]+\.jfrog\.io(:[0-9]+)?' terraform/platform/backend.tf 2>/dev/null | head -1 || true)
[ -z "$CURRENT_HOST" ] && CURRENT_HOST="$DEFAULT_EXAMPLE_HOST"

if [ "$CURRENT_HOST" = "$NEW_HOST" ]; then
  echo -e "${BLUE}Nothing to do${NC} — codebase already uses $NEW_HOST."
  exit 0
fi

echo -e "${BLUE}==> Substituting${NC} $CURRENT_HOST -> $NEW_HOST"

FILES=(
  "terraform/platform/backend.tf"
  "terraform/curation/backend.tf"
  ".github/scripts/intake_new_project.py"
)
for d in terraform/projects/*/; do
  [ -d "$d" ] || continue
  if [ -f "${d}backend.tf" ]; then
    FILES+=("${d}backend.tf")
  fi
done

changed=0
skipped=0
for f in "${FILES[@]}"; do
  if [ ! -f "$f" ]; then
    echo -e "  ${YELLOW}skip${NC}    $f  (not found)"
    skipped=$((skipped + 1))
    continue
  fi
  if grep -q "$CURRENT_HOST" "$f"; then
    sed -i.bak "s|$CURRENT_HOST|$NEW_HOST|g" "$f"
    rm -f "${f}.bak"
    echo -e "  ${GREEN}updated${NC} $f"
    changed=$((changed + 1))
  else
    echo -e "  ${YELLOW}skip${NC}    $f  (no '$CURRENT_HOST' string found)"
    skipped=$((skipped + 1))
  fi
done

echo
echo -e "${GREEN}Done.${NC} $changed file(s) updated, $skipped skipped."
echo
echo "Next steps:"
echo "  1. Verify the changes:    git diff"
echo "  2. (Optional) commit:     git add -A && git commit -m 'Set JFrog host to $NEW_HOST'"
echo "  3. Configure credentials: cp terraform/terraform.tfvars.example terraform/terraform.tfvars"
echo "                             and fill in jfrog_url + jfrog_access_token"
echo "  4. Run:                   cd terraform && ./run.sh --auto"
