#!/usr/bin/env bash
set -euo pipefail

# Chatvolt Interactive Tools Manager
# Usage: ./manage-tools.sh <api-key> <agent-id>

API_KEY="${1:?Usage: $0 <api-key> <agent-id>}"
AGENT_ID="${2:?Usage: $0 <api-key> <agent-id>}"
BASE_URL="https://api.chatvolt.ai"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   Chatvolt Tools Manager             ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"
echo "Agent: ${AGENT_ID}"
echo ""

# Get agent name
AGENT_NAME=$(curl -s "${BASE_URL}/agents/${AGENT_ID}" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get('name', 'N/A'))
except:
    print('N/A')
" 2>/dev/null || echo "N/A")
echo -e "${GREEN}Agent: ${AGENT_NAME}${NC}"
echo ""

main_menu() {
  while true; do
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${YELLOW}  1)${NC} List all tools"
    echo -e "${YELLOW}  2)${NC} View tool details"
    echo -e "${YELLOW}  3)${NC} Create a tool"
    echo -e "${YELLOW}  4)${NC} Update a tool"
    echo -e "${YELLOW}  5)${NC} Delete a tool"
    echo -e "${YELLOW}  6)${NC} Export all tools to JSON"
    echo -e "${YELLOW}  7)${NC} Exit"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    read -r -p "Choose option [1-7]: " OPTION

    case "$OPTION" in
      1) list_tools ;;
      2) view_tool ;;
      3) create_tool_menu ;;
      4) update_tool_menu ;;
      5) delete_tool_menu ;;
      6) export_tools ;;
      7) echo "Bye!"; exit 0 ;;
      *) echo -e "${RED}Invalid option${NC}" ;;
    esac
    echo ""
  done
}

list_tools() {
  echo ""
  echo -e "${CYAN}─── Tools ───${NC}"
  "${SCRIPT_DIR}/list-tools.sh" "$API_KEY" "$AGENT_ID"
  echo ""
  read -r -p "Press Enter to continue..."
}

view_tool() {
  echo ""
  read -r -p "Tool ID: " TOOL_ID
  if [ -z "$TOOL_ID" ]; then
    echo -e "${RED}No tool ID provided${NC}"
    return
  fi
  echo ""
  "${SCRIPT_DIR}/get-tool.sh" "$API_KEY" "$AGENT_ID" "$TOOL_ID"
  echo ""
  read -r -p "Press Enter to continue..."
}

create_tool_menu() {
  echo ""
  echo -e "${CYAN}─── Create Tool ───${NC}"
  echo "1) Datastore tool"
  echo "2) HTTP tool"
  echo "3) Form tool"
  echo "4) Cancel"
  read -r -p "Choose type [1-4]: " TYPE

  case "$TYPE" in
    1)
      read -r -p "Datastore ID: " DS_ID
      if [ -n "$DS_ID" ]; then
        "${SCRIPT_DIR}/create-tool.sh" "$API_KEY" "$AGENT_ID" datastore "$DS_ID"
      fi
      ;;
    2)
      echo "Enter HTTP tool configuration as JSON."
      echo "Press Ctrl+D (or type END on a new line) when done."
      echo "Example:"
      echo '{"config":{"name":"My API","description":"Description","url":"https://api.example.com","method":"GET"}}'
      echo "---"
      JSON=$(cat)
      if [ -n "$JSON" ]; then
        "${SCRIPT_DIR}/create-tool.sh" "$API_KEY" "$AGENT_ID" http "$JSON"
      fi
      ;;
    3)
      read -r -p "Form ID: " FORM_ID
      if [ -n "$FORM_ID" ]; then
        "${SCRIPT_DIR}/create-tool.sh" "$API_KEY" "$AGENT_ID" form "$FORM_ID"
      fi
      ;;
    4) return ;;
    *) echo -e "${RED}Invalid option${NC}" ;;
  esac
  echo ""
  read -r -p "Press Enter to continue..."
}

update_tool_menu() {
  echo ""
  read -r -p "Tool ID to update: " TOOL_ID
  if [ -z "$TOOL_ID" ]; then
    echo -e "${RED}No tool ID provided${NC}"
    return
  fi

  echo ""
  echo -e "${CYAN}─── Update Tool ───${NC}"
  echo "Enter the updated tool configuration as JSON."
  echo "Press Ctrl+D (or type END on a new line) when done."
  echo "Tip: run option 2 first to see current config."
  echo "---"
  JSON=$(cat)
  if [ -n "$JSON" ]; then
    "${SCRIPT_DIR}/update-tool.sh" "$API_KEY" "$AGENT_ID" "$TOOL_ID" "$JSON"
  fi
  echo ""
  read -r -p "Press Enter to continue..."
}

delete_tool_menu() {
  echo ""
  read -r -p "Tool ID to delete: " TOOL_ID
  if [ -z "$TOOL_ID" ]; then
    echo -e "${RED}No tool ID provided${NC}"
    return
  fi
  "${SCRIPT_DIR}/delete-tool.sh" "$API_KEY" "$AGENT_ID" "$TOOL_ID"
  echo ""
  read -r -p "Press Enter to continue..."
}

export_tools() {
  echo ""
  OUTFILE="chatvolt-tools-${AGENT_ID}-$(date +%Y%m%d-%H%M%S).json"
  echo "Exporting all tools to ${OUTFILE} ..."

  curl -s "${BASE_URL}/api/agents/${AGENT_ID}/tools" \
    -H "Authorization: Bearer ${API_KEY}" \
    -H "Content-Type: application/json" | python3 -m json.tool > "$OUTFILE" 2>/dev/null

  if [ -s "$OUTFILE" ]; then
    COUNT=$(python3 -c "import json; data=json.load(open('$OUTFILE')); print(len(data) if isinstance(data, list) else 0)")
    echo -e "${GREEN}✅ Exported ${COUNT} tool(s) to ${OUTFILE}${NC}"
  else
    echo -e "${RED}Failed to export tools${NC}"
    rm -f "$OUTFILE"
  fi
  echo ""
  read -r -p "Press Enter to continue..."
}

main_menu
