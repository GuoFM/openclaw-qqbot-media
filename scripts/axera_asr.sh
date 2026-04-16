#!/usr/bin/env bash
# Transcribe audio via OpenAI-compatible POST /v1/audio/transcriptions
# (same fields as Python: file, model, language).
#
# Axera ASR expects loadable WAV. QQ 下载的语音常为 .bin / SILK / AMR 等，本脚本先用 ffmpeg 转为
# 16kHz mono PCM WAV 再上传，并强制 multipart 文件名为 audio.wav，避免服务端 Unknown format / load wav failed。
set -euo pipefail

AUDIO="${1:?Usage: axera_asr.sh /absolute/path/to/audio}"
[[ -f "$AUDIO" ]] || { echo "axera_asr: file not found: $AUDIO" >&2; exit 1; }

URL="${AXERA_ASR_URL:-http://10.126.35.203:8090/v1/audio/transcriptions}"
MODEL="${AXERA_ASR_MODEL:-sensevoice}"
LANG="${AXERA_ASR_LANGUAGE:-zh}"
API_KEY="${AXERA_API_KEY:-dummy_key}"

TMP="$(mktemp)"
WAV_TMP=""
cleanup() { rm -f "$TMP" ${WAV_TMP:+"$WAV_TMP"}; }
trap cleanup EXIT

# 若已是 WAV 且 ffprobe 认为是 PCM，可直接上传；否则一律转码
UPLOAD="$AUDIO"
codec="$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$AUDIO" 2>/dev/null || true)"
if [[ "${AUDIO,,}" =~ \.wav$ ]] && [[ "$codec" == pcm_s16le || "$codec" == pcm_s24le || "$codec" == pcm_u8 ]]; then
  UPLOAD="$AUDIO"
else
  WAV_TMP="$(mktemp --suffix=.wav)"
  if ffmpeg -hide_banner -loglevel error -y -i "$AUDIO" -acodec pcm_s16le -ar 16000 -ac 1 "$WAV_TMP" 2>/dev/null; then
    UPLOAD="$WAV_TMP"
  elif ffmpeg -hide_banner -loglevel error -y -f silk -i "$AUDIO" -acodec pcm_s16le -ar 16000 -ac 1 "$WAV_TMP" 2>/dev/null; then
    UPLOAD="$WAV_TMP"
  else
    echo "axera_asr: ffmpeg cannot decode to WAV: $AUDIO (install ffmpeg; check format)" >&2
    exit 1
  fi
fi

# filename= 与 type= 避免服务端按 .bin 猜格式失败
curl -sS -X POST "$URL" \
  -H "Authorization: Bearer ${API_KEY}" \
  -F "file=@${UPLOAD};filename=audio.wav;type=audio/wav" \
  -F "model=${MODEL}" \
  -F "language=${LANG}" \
  -o "$TMP" || { echo "axera_asr: curl failed" >&2; exit 1; }

python3 - "$TMP" <<'PY'
import json, sys
path = sys.argv[1]
with open(path, "r", encoding="utf-8", errors="replace") as f:
    raw = f.read()
try:
    d = json.loads(raw)
except json.JSONDecodeError:
    print(raw.strip())
    sys.exit(0)
if isinstance(d, dict) and d.get("error"):
    print(json.dumps(d["error"], ensure_ascii=False), file=sys.stderr)
    sys.exit(1)
text = d.get("text")
if text is None:
    text = d.get("result") or d.get("transcript") or ""
if not isinstance(text, str):
    text = str(text)
print(text)
PY
