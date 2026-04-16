#!/usr/bin/env bash
# Synthesize speech via OpenAI-compatible POST /v1/audio/speech
# (same as OpenAI client: audio.speech.create).
#
# Axera TTS maps **language** into JSON field `instructions` (en | zh | ja), NOT a free-text prompt.
# `instructions` 始终由脚本根据合成正文（或纯音素串）自动检测，不读环境变量覆盖。
# Usage: axera_tts.sh OUTPUT_PATH [text...]   OR   echo text | axera_tts.sh OUTPUT_PATH
set -euo pipefail

OUT="${1:?Usage: axera_tts.sh /absolute/path/out_base_or_file [text...]}"
shift || true

TEXTFILE="$(mktemp)"
trap 'rm -f "$TEXTFILE"' EXIT

if [[ $# -gt 0 ]]; then
  printf '%s' "$*" > "$TEXTFILE"
else
  cat > "$TEXTFILE"
fi

[[ -s "$TEXTFILE" ]] || { echo "axera_tts: empty text" >&2; exit 1; }

# Default: TTS on port 8080 (override with AXERA_TTS_URL)
URL="${AXERA_TTS_URL:-http://172.17.0.1:8080/v1/audio/speech}"
MODEL="${AXERA_TTS_MODEL:-kokoro}"
VOICE="${AXERA_TTS_VOICE:-jm_kumo}"
SPEED="${AXERA_TTS_SPEED:-0.8}"
FMT="${AXERA_TTS_FORMAT:-wav}"
API_KEY="${AXERA_API_KEY:-dummy_key}"
export AXERA_TTS_PHONEMES="${AXERA_TTS_PHONEMES:-}"

export OUT URL MODEL VOICE SPEED FMT API_KEY TEXTFILE
python3 <<'PY'
import json, os, subprocess, sys

out = os.environ["OUT"]
url = os.environ["URL"]
model = os.environ["MODEL"]
voice = os.environ["VOICE"]

def detect_tts_lang(sample: str) -> str:
    """Map input to Axera instructions: en | zh | ja (heuristic, stdlib only)."""
    if not sample or not sample.strip():
        return "zh"
    t = "".join(sample.split())
    for ch in t:
        o = ord(ch)
        if 0x3040 <= o <= 0x309F:  # Hiragana
            return "ja"
        if 0x30A0 <= o <= 0x30FF:  # Katakana
            return "ja"
        if 0xFF66 <= o <= 0xFF9F:  # Halfwidth Katakana
            return "ja"
    cjk = latin = 0
    for ch in t:
        o = ord(ch)
        if 0x4E00 <= o <= 0x9FFF or 0x3400 <= o <= 0x4DBF:
            cjk += 1
        elif "A" <= ch <= "Z" or "a" <= ch <= "z":
            latin += 1
    if cjk > 0:
        return "zh"
    if latin > 0:
        return "en"
    return "zh"


def resolve_lang(text: str, phon: str) -> str:
    sample = text if text.strip() else phon
    return detect_tts_lang(sample)


try:
    speed = float(os.environ.get("SPEED", "0.8"))
except ValueError:
    speed = 0.8
fmt = os.environ.get("FMT", "wav").strip().lower() or "wav"
api_key = os.environ.get("API_KEY", "dummy_key")

with open(os.environ["TEXTFILE"], "r", encoding="utf-8") as f:
    text = f.read()

phon = os.environ.get("AXERA_TTS_PHONEMES", "").strip()
lang = resolve_lang(text, phon)
if phon:
    body = {
        "model": model,
        "voice": voice,
        "phonemes": phon,
        "instructions": lang,
        "speed": speed,
        "response_format": fmt,
    }
else:
    body = {
        "model": model,
        "voice": voice,
        "input": text,
        "instructions": lang,
        "speed": speed,
        "response_format": fmt,
    }

root, _ext = os.path.splitext(out)
out_path = root + "." + fmt

hdr = ["Authorization: Bearer " + api_key]
raw = subprocess.run(
    [
        "curl",
        "-sS",
        "-X",
        "POST",
        url,
        "-H",
        hdr[0],
        "-H",
        "Content-Type: application/json",
        "-d",
        json.dumps(body, ensure_ascii=False),
        "-o",
        out_path,
    ],
    capture_output=True,
    text=True,
)
if raw.returncode != 0:
    print(raw.stderr or raw.stdout, file=sys.stderr)
    raise SystemExit(raw.returncode or 1)

try:
    sz = os.path.getsize(out_path)
except OSError:
    sz = 0
if 0 < sz < 8192:
    with open(out_path, "rb") as f:
        head = f.read(1)
    if head == b"{":
        with open(out_path, "r", encoding="utf-8", errors="replace") as f:
            print(f.read(), file=sys.stderr)
        raise SystemExit(1)

print(out_path)
PY
