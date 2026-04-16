#!/usr/bin/env bash
# Uniform temporal sampling into frame_*.jpg (max 8 frames; AXERA_VIDEO_FRAMES capped in shell).
# VLM: axera_vlm_http.py sends one axllm video: chat (see AXERA_VIDEO_MODE base64|dir).
set -euo pipefail

VIDEO="${1:?Usage: axera_vlm_video.sh /path/to/video.mp4 [optional_user_prompt]}"
USER_Q="${2:-请用中文概括整段视频在讲什么、关键物体与场景变化；若有可见文字请列出。}"
[[ -f "$VIDEO" ]] || { echo "axera_vlm_video: file not found: $VIDEO" >&2; exit 1; }

command -v ffmpeg >/dev/null 2>&1 || { echo "axera_vlm_video: ffmpeg not found" >&2; exit 1; }
command -v ffprobe >/dev/null 2>&1 || { echo "axera_vlm_video: ffprobe not found" >&2; exit 1; }

# How many JPEGs to extract (never more than 8; HTTP layer applies stride/max again).
_raw="${AXERA_VIDEO_FRAMES:-8}"
case "${_raw}" in
  ''|*[!0-9]*) _raw=8 ;;
esac
[ "${_raw}" -gt 8 ] 2>/dev/null && _raw=8
NFRAMES="${_raw}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY="${SCRIPT_DIR}/axera_vlm_http.py"
[[ -f "$PY" ]] || { echo "axera_vlm_video: missing $PY" >&2; exit 1; }

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

DUR="$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$VIDEO" || true)"
python3 - "$WORKDIR" "$VIDEO" "$DUR" "$NFRAMES" <<'PY'
import os, subprocess, sys

work, video, dur_s, n_s = sys.argv[1:5]
try:
    duration = float(dur_s)
except ValueError:
    duration = 0.0
n = max(1, int(n_s))
if duration <= 0:
    duration = 1.0


def sample_times(T: float, count: int) -> list[float]:
    return [(i + 0.5) * T / count for i in range(count)]


for i, t in enumerate(sample_times(duration, n)):
    out = os.path.join(work, f"frame_{i:02d}.jpg")
    subprocess.run(
        [
            "ffmpeg",
            "-hide_banner",
            "-loglevel",
            "error",
            "-ss",
            str(t),
            "-i",
            video,
            "-frames:v",
            "1",
            "-q:v",
            "3",
            "-y",
            out,
        ],
        check=True,
    )
PY

exec python3 "$PY" video --workdir "$WORKDIR" --query "$USER_Q"
