#!/usr/bin/env nix-shell
#!nix-shell -i bash -p bash python3 curl
set -euo pipefail

# Anytype Mind Bootstrap Script
# Creates the complete type/property/tag/collection schema in Anytype
#
# Prerequisites:
#   - Anytype desktop app running
#   - API key created (Anytype Settings > API Keys)
#   - Set ANYTYPE_API_KEY environment variable
#
# Usage:
#   ANYTYPE_API_KEY="your-key-here" bash setup/bootstrap.sh /path/to/target/repo
#   ANYTYPE_API_KEY="your-key-here" bash setup/bootstrap.sh /path/to/target/repo --switch-space
#
# Optional:
#   ANYTYPE_API_DISABLE_RATE_LIMIT=1 to disable rate limiting during setup

# Parse arguments
TARGET_REPO=""
SWITCH_SPACE=false

for arg in "$@"; do
  if [ "$arg" = "--switch-space" ]; then
    SWITCH_SPACE=true
  elif [ -z "$TARGET_REPO" ]; then
    TARGET_REPO="$arg"
  fi
done

# Validate target repo
if [ -z "$TARGET_REPO" ]; then
  echo "Error: Target repo path not specified."
  echo "Usage: ANYTYPE_API_KEY='your-key' bash setup/bootstrap.sh /path/to/target/repo"
  exit 1
fi

if [ ! -d "$TARGET_REPO" ]; then
  echo "Error: Target repo does not exist: $TARGET_REPO"
  exit 1
fi

if [ ! -d "$TARGET_REPO/.git" ]; then
  echo "Error: Target repo is not a git repository (no .git directory found): $TARGET_REPO"
  exit 1
fi

# Convert to absolute path
TARGET_REPO="$(cd "$TARGET_REPO" && pwd)"
SPACE_FILE="$TARGET_REPO/.space.md"

API_BASE="http://localhost:31009/v1"
API_KEY="${ANYTYPE_API_KEY:?Set ANYTYPE_API_KEY environment variable}"
API_VERSION="2025-11-08"

auth_header="Authorization: Bearer $API_KEY"
version_header="Anytype-Version: $API_VERSION"
content_type="Content-Type: application/json"

# Temporary file for HTTP response code
HTTP_CODE_FILE=$(mktemp)

call_api() {
  local method="$1"
  local endpoint="$2"
  local data="${3:-}"
  local response_body
  local http_code

  # Clean up previous HTTP code
  rm -f "$HTTP_CODE_FILE"

  if [ -n "$data" ]; then
    response_body=$(curl -s -w "\n%{http_code}" -X "$method" "${API_BASE}${endpoint}" \
      -H "$auth_header" -H "$version_header" -H "$content_type" \
      -d "$data" 2>&1)
  else
    response_body=$(curl -s -w "\n%{http_code}" -X "$method" "${API_BASE}${endpoint}" \
      -H "$auth_header" -H "$version_header" 2>&1)
  fi

  # Extract HTTP code (last line) and body (everything else)
  http_code=$(echo "$response_body" | tail -n1)
  response_body=$(echo "$response_body" | sed '$d')

  # Store HTTP code for checking
  echo "$http_code" > "$HTTP_CODE_FILE"

  # Check for non-2xx status codes
  if [[ ! "$http_code" =~ ^2[0-9][0-9]$ ]]; then
    echo "ERROR: HTTP $http_code calling ${method} ${endpoint}" >&2
    echo "Request body: ${data:-<none>}" >&2
    echo "Response: $response_body" >&2
  fi

  echo "$response_body"
}

# Helper to check last HTTP status
get_last_http_code() {
  if [ -f "$HTTP_CODE_FILE" ]; then
    cat "$HTTP_CODE_FILE"
  else
    echo "unknown"
  fi
}

# Cleanup HTTP code file on exit
cleanup() {
  rm -f "$HTTP_CODE_FILE"
}
trap cleanup EXIT

# Read saved space from .space.md
read_saved_space() {
  if [ -f "$SPACE_FILE" ]; then
    grep '^space_id:' "$SPACE_FILE" | head -1 | sed 's/^space_id: *//'
  fi
}

read_saved_space_name() {
  if [ -f "$SPACE_FILE" ]; then
    grep '^space_name:' "$SPACE_FILE" | head -1 | sed 's/^space_name: *//'
  fi
}

# Write selected space to .space.md
save_space() {
  local id="$1" name="$2"
  cat > "$SPACE_FILE" <<EOF
---
space_id: $id
space_name: $name
updated: $(date +%Y-%m-%d)
---

# Default Anytype Space

This file stores your selected Anytype space for AI tools to use.
It is gitignored — each machine keeps its own.

To change: \`bash setup/bootstrap.sh /path/to/repo --switch-space\`
EOF
  echo "   Saved to $SPACE_FILE"
}

# Append .space.md to .gitignore
gitignore_add_space_file() {
  local gitignore="$TARGET_REPO/.gitignore"
  local entry=".space.md"

  if [ -f "$gitignore" ]; then
    # Check if entry already exists
    if grep -qF "$entry" "$gitignore" 2>/dev/null; then
      echo "   .gitignore already contains: $entry"
    else
      echo "" >> "$gitignore"
      echo "# Anytype Mind - machine-specific space configuration" >> "$gitignore"
      echo "$entry" >> "$gitignore"
      echo "   Appended to .gitignore: $entry"
    fi
  else
    echo "# Anytype Mind - machine-specific space configuration" > "$gitignore"
    echo "$entry" >> "$gitignore"
    echo "   Created .gitignore with: $entry"
  fi
}

# Copy Anytype Mind files to target repo
copy_files_to_repo() {
  local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local source_repo="$(dirname "$script_dir")"

  echo ">> Copying Anytype Mind files to target repo..."

  # Create .opencode directory structure
  mkdir -p "$TARGET_REPO/.opencode/agents"
  mkdir -p "$TARGET_REPO/.opencode/commands"

  # Copy agents (if they exist)
  if [ -d "$source_repo/.opencode/agents" ]; then
    echo "   Copying agents..."
    cp -r "$source_repo/.opencode/agents"/* "$TARGET_REPO/.opencode/agents/" 2>/dev/null || true
  fi

  # Copy commands (if they exist)
  if [ -d "$source_repo/.opencode/commands" ]; then
    echo "   Copying commands..."
    cp -r "$source_repo/.opencode/commands"/* "$TARGET_REPO/.opencode/commands/" 2>/dev/null || true
  fi

  # Copy opencode.jsonc
  if [ -f "$source_repo/.opencode/opencode.jsonc" ]; then
    echo "   Copying opencode.jsonc..."
    cp "$source_repo/.opencode/opencode.jsonc" "$TARGET_REPO/.opencode/opencode.jsonc"
  elif [ -f "$source_repo/opencode.jsonc" ]; then
    echo "   Copying opencode.jsonc..."
    cp "$source_repo/opencode.jsonc" "$TARGET_REPO/.opencode/opencode.jsonc"
  fi

  echo "   Files copied successfully"
}

# Prompt user to pick a space from a list
pick_space() {
  local spaces_json="$1"
  local space_count="$2"

  echo "$spaces_json" | python3 -c "
import sys, json
spaces = json.load(sys.stdin).get('data', [])
for i, s in enumerate(spaces, 1):
    print(f\"    {i}) {s['name']}  ({s['id']})\")
" 2>/dev/null
  echo ""
  printf "   Select a space [1-%s] or 'new' to create one: " "$space_count"
  read -r CHOICE

  if [ "$CHOICE" = "new" ]; then
    printf "   Space name [Mind]: "
    read -r NEW_NAME
    NEW_NAME="${NEW_NAME:-Mind}"
    echo ">> Creating '$NEW_NAME' space..."
    RESULT=$(call_api POST "/spaces" "{\"name\":\"$NEW_NAME\",\"description\":\"Personal knowledge base\"}")
    SPACE_ID=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null)
    SPACE_NAME="$NEW_NAME"
    echo "   Created space: $SPACE_ID"
  elif echo "$CHOICE" | grep -qE '^[0-9]+$' && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le "$space_count" ]; then
    SPACE_ID=$(echo "$spaces_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['data'][$CHOICE-1]['id'])" 2>/dev/null)
    SPACE_NAME=$(echo "$spaces_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['data'][$CHOICE-1]['name'])" 2>/dev/null)
    echo "   Using space: $SPACE_NAME ($SPACE_ID)"
  else
    echo "   Invalid choice. Aborting."
    exit 1
  fi
}

echo "=== Anytype Mind Bootstrap ==="
echo ""
echo "Target repo: $TARGET_REPO"
echo "API Base: $API_BASE"
echo ""

# Test API connectivity first
echo ">> Testing API connectivity..."
TEST_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "${API_BASE}/spaces" -H "$auth_header" -H "$version_header" 2>&1)
if [[ ! "$TEST_RESPONSE" =~ ^2[0-9][0-9]$ ]]; then
  echo "ERROR: Cannot connect to Anytype API at $API_BASE"
  echo "HTTP Status: $TEST_RESPONSE"
  echo ""
  echo "Please check:"
  echo "  1. Anytype desktop app is running"
  echo "  2. API is enabled in Settings > API Keys"
  echo "  3. ANYTYPE_API_KEY environment variable is set correctly"
  exit 1
fi
echo "   API connection successful (HTTP $TEST_RESPONSE)"
echo ""

# 0. Copy files to target repo
copy_files_to_repo

# 1. Add .space.md to .gitignore
gitignore_add_space_file

echo ""

# 2. Resolve space — saved, prompted, or created
SAVED_ID=$(read_saved_space)
SAVED_NAME=$(read_saved_space_name)

if [ -n "$SAVED_ID" ] && [ "$SWITCH_SPACE" = false ]; then
  echo ">> Using saved space: ${SAVED_NAME:-$SAVED_ID}"
  echo "   (from $SPACE_FILE — run with --switch-space to change)"
  SPACE_ID="$SAVED_ID"
  SPACE_NAME="${SAVED_NAME:-}"
else
  if [ "$SWITCH_SPACE" = true ]; then
    echo ">> Switching space..."
  else
    echo ">> Checking spaces..."
  fi

  SPACES_JSON=$(call_api GET "/spaces")
  SPACE_COUNT=$(echo "$SPACES_JSON" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('data',[])))" 2>/dev/null || echo "0")

  if [ "$SPACE_COUNT" -eq 0 ]; then
    echo "   No spaces found."
    echo ">> Creating 'Mind' space..."
    RESULT=$(call_api POST "/spaces" '{"name":"Mind","description":"Personal knowledge base"}')
    SPACE_ID=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null)
    SPACE_NAME="Mind"
    echo "   Created space: $SPACE_ID"
  elif [ "$SPACE_COUNT" -eq 1 ] && [ "$SWITCH_SPACE" = false ]; then
    SPACE_ID=$(echo "$SPACES_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['data'][0]['id'])" 2>/dev/null)
    SPACE_NAME=$(echo "$SPACES_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['data'][0]['name'])" 2>/dev/null)
    echo "   Using space: $SPACE_NAME ($SPACE_ID)"
  else
    echo "   Found $SPACE_COUNT spaces:"
    echo ""
    pick_space "$SPACES_JSON" "$SPACE_COUNT"
  fi

  save_space "$SPACE_ID" "${SPACE_NAME:-}"
fi

if [ -z "${SPACE_ID:-}" ]; then
  echo "Error: Failed to determine space ID."
  exit 1
fi

# If only switching space, stop here
if [ "$SWITCH_SPACE" = true ]; then
  echo ""
  echo "Space updated. Run without --switch-space to bootstrap types/properties."
  exit 0
fi

echo ""

# 3. Create properties
echo ">> Creating properties..."

get_prop_id() { eval echo "\${PROP_ID_$1:-}"; }

# Fetch existing property ID by key
fetch_property_id() {
  local key="$1"
  local properties_json
  properties_json=$(call_api GET "/spaces/$SPACE_ID/properties")
  echo "$properties_json" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for prop in data.get('data', []):
    if prop.get('key') == '$key':
        print(prop.get('id', ''))
        break
" 2>/dev/null
}

create_property() {
  local key="$1" name="$2" format="$3"
  echo "   Creating property: $name ($format)"
  RESULT=$(call_api POST "/spaces/$SPACE_ID/properties" \
    "{\"name\":\"$name\",\"key\":\"$key\",\"format\":\"$format\"}")
  HTTP_CODE=$(get_last_http_code)

  if [[ "$HTTP_CODE" =~ ^2[0-9][0-9]$ ]]; then
    PROP_ID=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")
    if [ -z "$PROP_ID" ]; then
      echo "   WARNING: Property '$name' created but could not extract ID"
      echo "   Response: $RESULT"
    else
      echo "   ✓ Created property: $name (ID: ${PROP_ID:0:8}...)"
    fi
  elif echo "$RESULT" | grep -q "already exists"; then
    echo "   ⚠ Property '$name' already exists, fetching ID..."
    PROP_ID=$(fetch_property_id "$key")
    if [ -n "$PROP_ID" ]; then
      echo "   ✓ Using existing property: $name (ID: ${PROP_ID:0:8}...)"
    else
      echo "   WARNING: Could not fetch ID for existing property '$name'"
    fi
  else
    echo "   FAILED to create property: $name (HTTP $HTTP_CODE)"
    echo "   Response: $RESULT"
    return 1
  fi

  eval "PROP_ID_${key}=\$PROP_ID"
  sleep 1
}

create_property "vault_tags" "Tags" "multi_select"
create_property "status" "Status" "select"
create_property "quarter" "Quarter" "select"
create_property "ticket" "Ticket" "text"
create_property "severity" "Severity" "select"
create_property "incident_role" "Incident Role" "select"
create_property "review_cycle" "Review Cycle" "select"
create_property "related_person" "Related Person" "objects"
create_property "related_team" "Related Team" "objects"
create_property "project_name" "Project" "text"
create_property "title" "Title" "text"

echo ""

# 4. Create tags for select/multi_select properties
echo ">> Creating tags for select properties..."

create_tag() {
  local prop_id="$1" tag_name="$2"
  local result
  result=$(call_api POST "/spaces/$SPACE_ID/properties/$prop_id/tags" \
    "{\"name\":\"$tag_name\",  \"color\": \"grey\"}")
  local http_code=$(get_last_http_code)

  if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
    : # Success, no output needed for tags
  elif echo "$result" | grep -qi "already exists"; then
    : # Tag already exists, silently continue
  else
    echo "     ERROR creating tag '$tag_name' for property $prop_id (HTTP $http_code)" >&2
    return 1
  fi
  sleep 0.5
}

# Status tags
PROP=$(get_prop_id status)
if [ -n "$PROP" ]; then
  echo "   Status tags..."
  for tag in active completed archived proposed accepted deprecated; do
    create_tag "$PROP" "$tag"
  done
fi

# Quarter tags
PROP=$(get_prop_id quarter)
if [ -n "$PROP" ]; then
  echo "   Quarter tags..."
  for year in 2025 2026 2027; do
    for q in Q1 Q2 Q3 Q4; do
      create_tag "$PROP" "${q}-${year}"
    done
  done
fi

# Severity tags
PROP=$(get_prop_id severity)
if [ -n "$PROP" ]; then
  echo "   Severity tags..."
  for tag in low medium high critical; do
    create_tag "$PROP" "$tag"
  done
fi

# Incident Role tags
PROP=$(get_prop_id incident_role)
if [ -n "$PROP" ]; then
  echo "   Incident Role tags..."
  for tag in incident-lead responder observer; do
    create_tag "$PROP" "$tag"
  done
fi

# Review Cycle tags
PROP=$(get_prop_id review_cycle)
if [ -n "$PROP" ]; then
  echo "   Review Cycle tags..."
  for tag in h1-2025 h2-2025 h1-2026 h2-2026 h1-2027 h2-2027; do
    create_tag "$PROP" "$tag"
  done
fi

# vault_tags tags
PROP=$(get_prop_id vault_tags)
if [ -n "$PROP" ]; then
  echo "   Vault tags..."
  for tag in work-note decision perf thinking north-star competency person team brain index moc incident evidence; do
    create_tag "$PROP" "$tag"
  done
fi

echo ""

# 5. Create types
echo ">> Creating types..."

create_type() {
  local key="$1" name="$2" icon="$3" layout="$4"
  echo "   Creating type: $name"
  local result
  result=$(call_api POST "/spaces/$SPACE_ID/types" \
    "{\"name\":\"$name\", \"plural_name\": \"${name}s\", \"key\":\"$key\",\"icon\": { \"format\": \"icon\", \"name\": \"$icon\", \"color\": \"yellow\"  },\"layout\":\"$layout\"}")
  local http_code=$(get_last_http_code)

  if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
    echo "     ✓ Created type: $name"
  elif echo "$result" | grep -q "already exists"; then
    echo "     ⚠ Type '$name' already exists"
  else
    echo "     ERROR creating type '$name' (HTTP $http_code)" >&2
    return 1
  fi
  sleep 1
}

create_type "work_note" "Work Note" "clipboard" "basic"
create_type "incident" "Incident" "warning" "basic"
create_type "one_on_one" "1:1 Note" "people" "basic"
create_type "decision" "Decision Record" "scale" "basic"
create_type "person" "Person" "person" "profile"
create_type "team" "Team" "people" "basic"
create_type "competency" "Competency" "star" "basic"
create_type "pr_analysis" "PR Analysis" "code" "basic"
create_type "review_brief" "Review Brief" "document" "basic"
create_type "brain_note" "Brain Note" "book" "basic"
create_type "brag_entry" "Brag Entry" "trophy" "basic"
create_type "thinking_note" "Thinking Note" "bulb" "basic"

echo ""

# 6. Create key brain_note objects
echo ">> Creating key brain note objects..."

create_brain_note() {
  local name="$1" desc="$2" body="$3"
  echo "   Creating: $name"
  local result
  result=$(call_api POST "/spaces/$SPACE_ID/objects" \
    "{\"name\":\"$name\",\"type_key\":\"brain_note\",\"description\":\"$desc\",\"body\":\"$body\"}")
  local http_code=$(get_last_http_code)

  if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
    echo "     ✓ Created: $name"
  elif echo "$result" | grep -qi "already exists"; then
    echo "     ⚠ Brain note '$name' already exists"
  else
    echo "     ERROR creating brain note '$name' (HTTP $http_code)" >&2
    return 1
  fi
  sleep 1
}

create_brain_note "North Star" "Living goals document — read at session start" "# North Star\n\n## Current Focus\n\n- \n\n## Short-term Goals\n\n- \n\n## Medium-term Goals\n\n- \n\n## Anti-Goals\n\n- \n\n## Shifts Log\n\n| Date | Shift | Reason |\n|------|-------|--------|\n"
create_brain_note "Memories" "Index of memory topics — links to other brain_notes" "# Memories\n\nPersistent context retained across sessions. Each topic lives in its own brain_note.\n\n- North Star — living goals document\n- Key Decisions — architectural and workflow decisions\n- Patterns — recurring conventions\n- Gotchas — things that have bitten before\n- Skills — custom commands and workflows\n\n## Recent Context\n\n-"
create_brain_note "Key Decisions" "Architectural and workflow decisions worth recalling" "# Key Decisions\n\nDecisions that shape how we work. Each entry links to the decision object.\n\n-"
create_brain_note "Patterns" "Recurring patterns and conventions discovered across work" "# Patterns\n\nConventions and patterns observed across projects and sessions.\n\n-"
create_brain_note "Gotchas" "Things that have bitten before and will bite again" "# Gotchas\n\nKnown pitfalls and traps. Check here before repeating mistakes.\n\n-"
create_brain_note "Skills" "Custom slash commands, workflows, and agent capabilities" "# Skills\n\nRegistry of available commands and workflows.\n\nSee SKILL.md for the full command table and agent list."

echo ""

# 7. Create collections
echo ">> Creating collections..."

create_collection() {
  local name="$1" desc="$2"
  echo "   Creating collection: $name"
  local result
  result=$(call_api POST "/spaces/$SPACE_ID/objects" \
    "{\"name\":\"$name\",\"type_key\":\"collection\",\"description\":\"$desc\"}")
  local http_code=$(get_last_http_code)

  if [[ ! "$http_code" =~ ^2[0-9][0-9]$ ]]; then
    echo "     ERROR creating collection '$name' (HTTP $http_code)" >&2
    return 1
  else
    echo "     ✓ Created collection: $name"
  fi
  sleep 1
}

create_collection "Active Work" "Current active projects (work_note with status=active)"
create_collection "Archived Work" "Completed projects (work_note with status=completed)"
create_collection "Incidents" "All incident records"
create_collection "1:1 Notes" "Meeting notes from 1-on-1 conversations"
create_collection "People" "Organization directory"
create_collection "Teams" "Team directory"
create_collection "Brag Entries" "Achievement log"
create_collection "Evidence" "PR analyses and review evidence"
create_collection "Competencies" "Skill definitions"
create_collection "Brain Notes" "Operational knowledge"
create_collection "Mind Dashboard" "All key objects — curated overview"

echo ""
echo "=== Bootstrap Complete ==="
echo ""
echo "Space: ${SPACE_NAME:-$SPACE_ID} ($SPACE_ID)"
echo "Target: $TARGET_REPO"
echo "Saved: $SPACE_FILE"
echo ""
echo "Next steps:"
echo "  1. Verify in Anytype app that types, properties, and collections were created"
echo "  2. Review copied files in $TARGET_REPO/.opencode/"
echo "  3. Configure MCP server in your AI tool (see $TARGET_REPO/.opencode/opencode.jsonc)"
echo ""
echo "To change the default space later:"
echo "  bash setup/bootstrap.sh $TARGET_REPO --switch-space"
