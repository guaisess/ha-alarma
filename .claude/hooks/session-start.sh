#!/bin/bash
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

npx --yes skills add vercel-labs/skills --skill find-skills -g -y --agent claude-code
