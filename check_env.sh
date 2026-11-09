#!/usr/bin/env bash
# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# ==============================================================================
# Cloud Day Athens 2026: Workshop Environment Check & Setup (check_env.sh)
# Session: Vibe Code a 2D Game with Gemini and Antigravity 2.0
# ==============================================================================

set -u

AUTO_FIX=0
ARG_PROJECT_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fix|--install|--setup)
      AUTO_FIX=1
      if [[ $# -gt 1 && "${2:-}" != -* ]]; then
        ARG_PROJECT_ID="$2"
        shift
      fi
      shift
      ;;
    --project|-p)
      ARG_PROJECT_ID="${2:-}"
      shift 2
      ;;
    -h|--help)
      cat <<EOF
Usage: $(basename "$0") [--fix [YOUR_PROJECT_ID]]

Validates and configures all system, Google Cloud (Vertex AI / Gemini Enterprise),
and Antigravity 2.0 prerequisites for the Cloud Day Athens 2026 workshop:

  1. System Toolchain:
     - Go 1.26+ (for Ebitengine v2 and WebAssembly compilation)
     - Go WebAssembly runtime asset (wasm_exec.js in GOROOT)
     - Google Cloud SDK (gcloud CLI)
     - Antigravity 2.0 or Antigravity CLI (agy)
     - uv (Python package & script runner for banana.py, lyria.py, and omni.py)
     - python3 (Python 3.10+ runtime)
     - git

  2. Google Cloud Project, Billing Project & Vertex AI APIs:
     - Active GCP Project ID (gcloud config set project YOUR_PROJECT_ID)
     - Vertex AI Application Default Credentials (gcloud auth application-default login --billing-project YOUR_PROJECT_ID)
     - ADC quota_project_id configured in application_default_credentials.json
     - Required GCP APIs enabled:
         * aiplatform.googleapis.com         (Vertex AI / Gemini Enterprise)
         * developerknowledge.googleapis.com (Google Cloud Developer MCP)
         * run.googleapis.com                (Cloud Run game deployment)
         * cloudbuild.googleapis.com         (Cloud Build container builds)
         * artifactregistry.googleapis.com   (Artifact Registry)

  3. Antigravity Plugins:
     - agy-game-studio (Required): https://github.com/danicat/agy-game-studio
     - google-cloud-developer (Required): https://github.com/google/skills/tree/main/plugins/cloud/google-cloud-developer

Options:
  --fix [PROJECT_ID]   Install missing tools/plugins, authenticate Vertex AI ADC with
                       your billing project, and enable required GCP APIs
  -h, --help           Show this help message
EOF
      exit 0
      ;;
    *)
      if [[ -z "$ARG_PROJECT_ID" && "$1" != -* ]]; then
        ARG_PROJECT_ID="$1"
      fi
      shift
      ;;
  esac
done

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

ERRORS=0
WARNINGS=0
REMEDIATIONS=()
NOTES=()

REQUIRED_APIS=(
  "aiplatform.googleapis.com"
  "developerknowledge.googleapis.com"
  "run.googleapis.com"
  "cloudbuild.googleapis.com"
  "artifactregistry.googleapis.com"
)

record_row() {
  local component="$1"
  local status="$2"
  local details="$3"
  local fix="${4:-}"

  local color="$GREEN"
  if [[ "$status" == "FAIL" ]]; then
    color="$RED"
    ERRORS=$((ERRORS + 1))
    [[ -n "$fix" ]] && REMEDIATIONS+=("${BOLD}${component}${NC}: ${fix}")
  elif [[ "$status" == "WARN" ]]; then
    color="$YELLOW"
    WARNINGS=$((WARNINGS + 1))
    [[ -n "$fix" ]] && NOTES+=("${BOLD}${component}${NC}: ${fix}")
  fi

  printf "│ %-30s │ ${color}%-6s${NC} │ %-44s │\n" "${component:0:30}" "$status" "${details:0:44}"
}

# Ensure GOPATH/bin and ~/.local/bin are in PATH for this script
export PATH="$PATH:$HOME/.local/bin"
if command -v go >/dev/null 2>&1; then
  GOBIN_DIR="$(go env GOBIN 2>/dev/null || true)"
  if [[ -z "$GOBIN_DIR" ]]; then
    GOBIN_DIR="$(go env GOPATH 2>/dev/null || echo "$HOME/go")/bin"
  fi
  export PATH="$PATH:$GOBIN_DIR"
fi

# Resolve Project ID from argument, environment, or gcloud config
GCP_PROJECT="${ARG_PROJECT_ID:-${GOOGLE_CLOUD_PROJECT:-}}"
if [[ -z "$GCP_PROJECT" ]] && command -v gcloud >/dev/null 2>&1; then
  GCP_PROJECT="$(gcloud config get-value project 2>/dev/null || true)"
  [[ "$GCP_PROJECT" == "(unset)" ]] && GCP_PROJECT=""
fi

ADC_FILE="${GOOGLE_APPLICATION_CREDENTIALS:-$HOME/.config/gcloud/application_default_credentials.json}"

# ==============================================================================
# Optional Automated Setup (--fix [YOUR_PROJECT_ID])
# ==============================================================================
if [[ "$AUTO_FIX" -eq 1 ]]; then
  echo -e "${BLUE}${BOLD}==========================================================================================${NC}"
  echo -e "${BLUE}${BOLD}        Running Automated Workshop Setup (--fix)                                          ${NC}"
  echo -e "${BLUE}${BOLD}==========================================================================================${NC}"

  if [[ -z "$GCP_PROJECT" ]]; then
    echo -e "${YELLOW}No GCP Project ID detected.${NC}"
    read -r -p "Enter your Google Cloud Project ID (or press Enter to skip GCP setup): " GCP_PROJECT
  fi

  # 1. Install Antigravity CLI (agy) if neither agy nor Antigravity 2.0 is present
  if ! command -v agy >/dev/null 2>&1 && ! command -v antigravity >/dev/null 2>&1 && [[ ! -d "/Applications/Antigravity.app" ]]; then
    echo -e "\n${BOLD}-> Installing Antigravity CLI (agy)...${NC}"
    curl -fsSL https://antigravity.google/cli/install.sh | bash || true
  fi

  # 2. Install uv if missing
  if ! command -v uv >/dev/null 2>&1; then
    echo -e "\n${BOLD}-> Installing uv Python package runner...${NC}"
    curl -LsSf https://astral.sh/uv/install.sh | sh || true
  fi

  # 3. Install Antigravity plugins if missing
  mkdir -p "$HOME/.gemini/config/plugins"
  if [[ ! -d "$HOME/.gemini/config/plugins/agy-game-studio" && ! -d ".agents/plugins/agy-game-studio" ]]; then
    echo -e "\n${BOLD}-> Installing agy-game-studio plugin...${NC}"
    git clone https://github.com/danicat/agy-game-studio.git "$HOME/.gemini/config/plugins/agy-game-studio" || true
  fi
  if [[ ! -d "$HOME/.gemini/config/plugins/google-cloud-developer" && ! -d ".agents/plugins/google-cloud-developer" ]]; then
    echo -e "\n${BOLD}-> Installing google-cloud-developer plugin...${NC}"
    TMP_SKILLS="$(mktemp -d)"
    if git clone --depth 1 https://github.com/google/skills.git "$TMP_SKILLS"; then
      cp -R "$TMP_SKILLS/plugins/cloud/google-cloud-developer" "$HOME/.gemini/config/plugins/google-cloud-developer"
    fi
    rm -rf "$TMP_SKILLS"
  fi

  # 4. Configure GCP Project, APIs, and Vertex AI ADC + Billing Project
  if [[ -n "$GCP_PROJECT" ]] && command -v gcloud >/dev/null 2>&1; then
    echo -e "\n${BOLD}-> Setting active gcloud project to ${GCP_PROJECT}...${NC}"
    gcloud config set project "$GCP_PROJECT"

    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | grep -q .; then
      echo -e "\n${BOLD}-> Logging in to gcloud CLI...${NC}"
      gcloud auth login --project="$GCP_PROJECT" || gcloud auth login
    fi

    echo -e "\n${BOLD}-> Enabling required Google Cloud APIs on ${GCP_PROJECT}...${NC}"
    gcloud services enable "${REQUIRED_APIS[@]}" --project="$GCP_PROJECT"

    if ! gcloud auth application-default print-access-token >/dev/null 2>&1; then
      echo -e "\n${BOLD}-> Authenticating Application Default Credentials with billing project ${GCP_PROJECT}...${NC}"
      gcloud auth application-default login --billing-project "$GCP_PROJECT"
    else
      echo -e "\n${BOLD}-> Setting ADC billing/quota project to ${GCP_PROJECT}...${NC}"
      gcloud auth application-default set-quota-project "$GCP_PROJECT" || true
    fi
  fi
  echo ""
fi

echo -e "${BLUE}${BOLD}==========================================================================================${NC}"
echo -e "${BLUE}${BOLD}        Cloud Day Athens 2026: Vibe Code a 2D Game Workshop Environment Check             ${NC}"
echo -e "${BLUE}${BOLD}==========================================================================================${NC}"
echo ""
printf "┌────────────────────────────────┬────────┬──────────────────────────────────────────────┐\n"
printf "│ %-30s │ %-6s │ %-44s │\n" "Component" "Status" "Details"
printf "├────────────────────────────────┼────────┼──────────────────────────────────────────────┤\n"

# 1. Check Go (1.26+)
if command -v go >/dev/null 2>&1; then
  GO_RAW="$(go version | awk '{print $3}')"
  GO_VER="${GO_RAW#go}"
  GO_MAJOR="$(echo "$GO_VER" | cut -d. -f1)"
  GO_MINOR="$(echo "$GO_VER" | cut -d. -f2)"
  if [[ "$GO_MAJOR" -gt 1 ]] || { [[ "$GO_MAJOR" -eq 1 ]] && [[ "$GO_MINOR" -ge 26 ]]; }; then
    record_row "Go (1.26+)" "PASS" "Go ${GO_VER} installed"
  else
    record_row "Go (1.26+)" "FAIL" "Go ${GO_VER} found (1.26+ required)" \
      "Upgrade Go to 1.26+: https://go.dev/dl/ or 'brew upgrade go'"
  fi
else
  record_row "Go (1.26+)" "FAIL" "go binary not found in PATH" \
    "Install Go 1.26+: https://go.dev/dl/ or 'brew install go'"
fi

# 2. Check Go WebAssembly Support (wasm_exec.js)
if command -v go >/dev/null 2>&1; then
  GOROOT_PATH="$(go env GOROOT)"
  if [[ -f "${GOROOT_PATH}/lib/wasm/wasm_exec.js" ]]; then
    record_row "wasm_exec.js" "PASS" "Found in GOROOT/lib/wasm/wasm_exec.js"
  elif [[ -f "${GOROOT_PATH}/misc/wasm/wasm_exec.js" ]]; then
    record_row "wasm_exec.js" "PASS" "Found in GOROOT/misc/wasm/wasm_exec.js"
  else
    record_row "wasm_exec.js" "FAIL" "Missing wasm_exec.js in ${GOROOT_PATH}" \
      "Reinstall Go 1.26+ standard library from https://go.dev/dl/"
  fi
else
  record_row "wasm_exec.js" "FAIL" "Cannot check (go not installed)" \
    "Install Go 1.26+ first"
fi

# 3. Check gcloud CLI
if command -v gcloud >/dev/null 2>&1; then
  record_row "gcloud CLI" "PASS" "Google Cloud SDK installed"
else
  record_row "gcloud CLI" "FAIL" "gcloud binary not found in PATH" \
    "Install Google Cloud SDK: https://cloud.google.com/sdk/docs/install"
fi

# 4. Check Active GCP Project ID
TARGET_PROJ="${GCP_PROJECT:-YOUR_PROJECT_ID}"
if [[ -n "$GCP_PROJECT" ]]; then
  record_row "GCP Project ID" "PASS" "Project: ${GCP_PROJECT}"
else
  record_row "GCP Project ID" "FAIL" "No active GCP Project ID set" \
    "gcloud config set project YOUR_PROJECT_ID"
fi

# 5. Check Vertex AI Application Default Credentials (ADC)
ADC_TOKEN_VALID=0
if command -v gcloud >/dev/null 2>&1 && gcloud auth application-default print-access-token >/dev/null 2>&1; then
  ADC_TOKEN_VALID=1
  record_row "Vertex AI ADC" "PASS" "Application Default Credentials active"
else
  record_row "Vertex AI ADC" "FAIL" "ADC credentials missing or expired" \
    "gcloud auth application-default login --billing-project ${TARGET_PROJ}"
fi

# 6. Check ADC Billing / Quota Project (quota_project_id in application_default_credentials.json)
ADC_QUOTA_PROJ=""
if [[ -f "$ADC_FILE" ]]; then
  ADC_QUOTA_PROJ="$(grep -o '"quota_project_id"[[:space:]]*:[[:space:]]*"[^"]*"' "$ADC_FILE" 2>/dev/null | sed -E 's/.*"([^"]+)"$/\1/' || true)"
fi

if [[ -n "$ADC_QUOTA_PROJ" ]]; then
  if [[ -n "$GCP_PROJECT" && "$ADC_QUOTA_PROJ" != "$GCP_PROJECT" ]]; then
    record_row "ADC Billing Project" "WARN" "ADC (${ADC_QUOTA_PROJ}) != ${GCP_PROJECT}" \
      "gcloud auth application-default set-quota-project ${GCP_PROJECT}"
  else
    record_row "ADC Billing Project" "PASS" "quota_project_id: ${ADC_QUOTA_PROJ}"
  fi
else
  record_row "ADC Billing Project" "FAIL" "quota_project_id not set in ADC" \
    "gcloud auth application-default login --billing-project ${TARGET_PROJ} (or: gcloud auth application-default set-quota-project ${TARGET_PROJ})"
fi

# 7. Check Required Google Cloud APIs on Project
if [[ -n "$GCP_PROJECT" ]] && command -v gcloud >/dev/null 2>&1 && [[ "$ADC_TOKEN_VALID" -eq 1 ]]; then
  ENABLED_SERVICES="$(gcloud services list --enabled --project="$GCP_PROJECT" --format="value(config.name)" 2>/dev/null || true)"
  if [[ -n "$ENABLED_SERVICES" ]]; then
    MISSING_APIS=()
    for api in "${REQUIRED_APIS[@]}"; do
      if ! echo "$ENABLED_SERVICES" | grep -q "^${api}$"; then
        MISSING_APIS+=("$api")
      fi
    done
    if [[ "${#MISSING_APIS[@]}" -eq 0 ]]; then
      record_row "GCP Required APIs" "PASS" "All 5 workshop APIs enabled"
    else
      record_row "GCP Required APIs" "FAIL" "Missing ${#MISSING_APIS[@]} API(s): ${MISSING_APIS[0]}..." \
        "gcloud services enable ${REQUIRED_APIS[*]} --project=${GCP_PROJECT}"
    fi
  else
    record_row "GCP Required APIs" "WARN" "Could not query enabled services" \
      "gcloud services enable ${REQUIRED_APIS[*]} --project=${GCP_PROJECT}"
  fi
else
  record_row "GCP Required APIs" "FAIL" "Cannot verify until Project & ADC are set" \
    "gcloud services enable ${REQUIRED_APIS[*]} --project=${TARGET_PROJ}"
fi

# 8. Check Antigravity 2.0 / agy CLI
if command -v agy >/dev/null 2>&1; then
  AGY_VER="$(agy --version 2>&1 | head -n1)"
  record_row "Antigravity (agy)" "PASS" "agy CLI installed (${AGY_VER})"
elif command -v antigravity >/dev/null 2>&1; then
  AGY_VER="$(antigravity --version 2>&1 | head -n1)"
  record_row "Antigravity (agy)" "PASS" "antigravity CLI installed (${AGY_VER})"
elif [[ -d "/Applications/Antigravity.app" || -d "$HOME/.gemini/antigravity" ]]; then
  record_row "Antigravity 2.0" "PASS" "Antigravity 2.0 detected"
else
  record_row "Antigravity 2.0 / agy" "FAIL" "Neither Antigravity 2.0 nor agy CLI found" \
    "Download Antigravity 2.0 from https://antigravity.google/download or install agy CLI: 'curl -fsSL https://antigravity.google/cli/install.sh | bash'"
fi

# 9. Check uv
if command -v uv >/dev/null 2>&1; then
  UV_VER="$(uv --version 2>&1 | head -n1)"
  record_row "uv" "PASS" "${UV_VER}"
else
  record_row "uv" "FAIL" "uv binary not found in PATH" \
    "Install uv: 'curl -LsSf https://astral.sh/uv/install.sh | sh' or 'brew install uv'"
fi

# 10. Check python3
if command -v python3 >/dev/null 2>&1; then
  PY_VER="$(python3 --version 2>&1 | head -n1)"
  record_row "python3" "PASS" "${PY_VER}"
else
  record_row "python3" "FAIL" "python3 binary not found in PATH" \
    "Install Python 3.10+: https://www.python.org/downloads/ or 'brew install python'"
fi

# 11. Check git
if command -v git >/dev/null 2>&1; then
  GIT_VER="$(git --version 2>&1 | head -n1)"
  record_row "git" "PASS" "${GIT_VER}"
else
  record_row "git" "FAIL" "git binary not found" \
    "Install git: https://git-scm.com/ or 'brew install git'"
fi

printf "├────────────────────────────────┼────────┼──────────────────────────────────────────────┤\n"

# Helper to check if an Antigravity plugin is installed
check_plugin() {
  local plugin_name="$1"
  local required="$2"
  local install_hint="$3"

  local found_path=""
  if [[ -d "$HOME/.gemini/config/plugins/${plugin_name}" ]]; then
    found_path="~/.gemini/config/plugins/${plugin_name}"
  elif [[ -d ".agents/plugins/${plugin_name}" ]]; then
    found_path=".agents/plugins/${plugin_name}"
  elif [[ -d "$HOME/.gemini/config/plugins" ]]; then
    local match
    match="$(grep -l "\"name\"[[:space:]]*:[[:space:]]*\"${plugin_name}\"" "$HOME"/.gemini/config/plugins/*/plugin.json "$HOME"/.gemini/config/plugins/*/.antigravity-plugin/plugin.json 2>/dev/null | head -n1 || true)"
    if [[ -n "$match" ]]; then
      found_path="~/.gemini/config/plugins (Marketplace)"
    fi
  fi

  if [[ -z "$found_path" ]] && command -v agy >/dev/null 2>&1; then
    if agy plugin list 2>/dev/null | grep -q -E "^- ${plugin_name} "; then
      found_path="Installed via agy plugin"
    fi
  fi

  if [[ -n "$found_path" ]]; then
    record_row "Plugin: ${plugin_name}" "PASS" "${found_path}"
  elif [[ "$required" == "required" ]]; then
    record_row "Plugin: ${plugin_name}" "FAIL" "Not installed (Required)" "$install_hint"
  else
    record_row "Plugin: ${plugin_name}" "WARN" "Not installed (Optional, recommended)" "$install_hint"
  fi
}

# 12. Check Antigravity Plugins
check_plugin "agy-game-studio" "required" \
  "git clone https://github.com/danicat/agy-game-studio.git ~/.gemini/config/plugins/agy-game-studio"

check_plugin "google-cloud-developer" "required" \
  "In Antigravity 2.0: Customizations > Marketplace > 'Google Cloud Developer' (or run './check_env.sh --fix ${TARGET_PROJ}')"

printf "└────────────────────────────────┴────────┴──────────────────────────────────────────────┘\n"

if [[ "$WARNINGS" -gt 0 ]]; then
  echo ""
  echo -e "${YELLOW}${BOLD}Recommended / Optional Steps:${NC}"
  for note in "${NOTES[@]}"; do
    echo -e "  • ${note}"
  done
fi

if [[ "$ERRORS" -gt 0 ]]; then
  echo ""
  echo -e "${RED}${BOLD}❌ ENVIRONMENT CHECK FAILED: ${ERRORS} required item(s) need attention.${NC}"
  echo -e "${YELLOW}${BOLD}Itemized Fixes:${NC}"
  for fix in "${REMEDIATIONS[@]}"; do
    echo -e "  • ${fix}"
  done
  echo ""
  echo -e "${BLUE}${BOLD}==========================================================================================${NC}"
  echo -e "${BLUE}${BOLD}  🚀 SINGLE-COMMAND FIX: Configure Everything Automatically                               ${NC}"
  echo -e "${BLUE}${BOLD}==========================================================================================${NC}"
  echo -e "Run this script with ${BOLD}--fix${NC} and your Google Cloud Project ID:"
  echo ""
  echo -e "  ${GREEN}${BOLD}./check_env.sh --fix ${TARGET_PROJ}${NC}"
  echo ""
  echo -e "💡 After setup completes, reload Antigravity 2.0 with ${BOLD}Cmd+Shift+R${NC} (${BOLD}Ctrl+Shift+R${NC} on Windows/Linux) to load newly installed plugins."
  echo ""
  echo -e "Or run the full setup manually with a single copy-paste block:"
  echo ""
  cat <<EOF
  export PROJECT_ID="${TARGET_PROJ}"
  gcloud config set project "\$PROJECT_ID"
  gcloud services enable \\
    aiplatform.googleapis.com \\
    developerknowledge.googleapis.com \\
    run.googleapis.com \\
    cloudbuild.googleapis.com \\
    artifactregistry.googleapis.com \\
    --project="\$PROJECT_ID"
  gcloud auth application-default login --billing-project "\$PROJECT_ID"
EOF
  echo ""
  exit 1
fi

echo ""
echo -e "${GREEN}${BOLD}🎉 ENVIRONMENT CHECK PASSED! All tools, plugins, APIs, and billing project credentials are ready.${NC}"
echo -e "${BLUE}${BOLD}💡 Hint:${NC} Reload Antigravity 2.0 with ${BOLD}Cmd+Shift+R${NC} (or ${BOLD}Ctrl+Shift+R${NC} on Windows/Linux) to apply plugin and setup changes."
exit 0
