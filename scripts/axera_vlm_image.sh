#!/usr/bin/env bash
# One image -> local VLM. Uses axera_vlm_http.py (urllib JSON POST, no curl — avoids huge argv).
set -euo pipefail

IMG="${1:?Usage: axera_vlm_image.sh /path/to/image.jpg [optional_user_prompt | --prompt-file PATH]}"
[[ -f "$IMG" ]] || { echo "axera_vlm_image: file not found: $IMG" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY="${SCRIPT_DIR}/axera_vlm_http.py"
[[ -f "$PY" ]] || { echo "axera_vlm_image: missing $PY" >&2; exit 1; }

if [[ "${2:-}" == "--prompt-file" ]]; then
  PF="${3:?Usage: axera_vlm_image.sh IMAGE --prompt-file /path/to/prompt.txt}"
  [[ -f "$PF" ]] || { echo "axera_vlm_image: prompt file not found: $PF" >&2; exit 1; }
  exec python3 "$PY" image "$IMG" "" --prompt-file "$PF"
elif [[ -n "${2:-}" ]]; then
  exec python3 "$PY" image "$IMG" "$2"
else
  exec python3 "$PY" image "$IMG" ""
fi
