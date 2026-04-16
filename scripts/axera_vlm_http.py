#!/usr/bin/env python3
"""
OpenAI-compatible POST /v1/chat/completions for Axera VLM — no curl.
Builds JSON in memory and sends via urllib (avoids shell/curl argv limits on large base64).
"""
from __future__ import annotations

import argparse
import base64
import json
import mimetypes
import os
import shutil
import sys
import urllib.error
import urllib.request
from pathlib import Path

# Single video request must never use more than this many frames (KV / prefill budget).
VIDEO_MAX_FRAMES_HARD_CAP = 8


def post_chat_completions(payload: dict, *, timeout: float = 120.0) -> dict:
    base = (os.environ.get("AXERA_VLM_BASE") or "http://10.126.35.203:8000/v1").rstrip("/")
    url = f"{base}/chat/completions"
    api_key = os.environ.get("AXERA_API_KEY", "dummy_key")
    data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as e:
        raise RuntimeError(e.read().decode("utf-8", errors="replace")) from e
    return json.loads(raw)


def extract_assistant_text(d: dict) -> str:
    if isinstance(d, dict) and d.get("error"):
        raise RuntimeError(json.dumps(d["error"], ensure_ascii=False))
    choices = d.get("choices") or []
    if not choices:
        return json.dumps(d, ensure_ascii=False)
    msg = choices[0].get("message") or {}
    content = msg.get("content")
    if isinstance(content, list):
        parts: list[str] = []
        for p in content:
            if isinstance(p, dict) and p.get("type") == "text":
                parts.append(p.get("text") or "")
        content = "".join(parts)
    if not isinstance(content, str):
        content = str(content or "")
    return content.strip()


def _mime_for_path(image_path: str) -> str:
    mime, _ = mimetypes.guess_type(image_path)
    if mime and mime.startswith("image/"):
        return mime
    ext = Path(image_path).suffix.lower()
    return {
        ".jpg": "image/jpeg",
        ".jpeg": "image/jpeg",
        ".png": "image/png",
        ".gif": "image/gif",
        ".webp": "image/webp",
        ".bmp": "image/bmp",
    }.get(ext, "image/jpeg")


def one_image_chat(image_path: str, prompt: str, *, max_tokens: int) -> str:
    model = os.environ.get("AXERA_VLM_MODEL") or "AXERA-TECH/Qwen3-VL-2B-Instruct"
    mime = _mime_for_path(image_path)
    b64 = base64.standard_b64encode(Path(image_path).read_bytes()).decode("ascii")
    data_url = f"data:{mime};base64,{b64}"
    body = {
        "model": model,
        "messages": [
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": prompt},
                    {"type": "image_url", "image_url": {"url": data_url}},
                ],
            }
        ],
        "max_tokens": max_tokens,
    }
    return extract_assistant_text(post_chat_completions(body))


def multi_image_chat(image_paths: list[str], prompt: str, *, max_tokens: int) -> str:
    model = os.environ.get("AXERA_VLM_MODEL") or "AXERA-TECH/Qwen3-VL-2B-Instruct"
    content: list[dict] = [{"type": "text", "text": prompt}]
    for p in image_paths:
        mime = _mime_for_path(p)
        b64 = base64.standard_b64encode(Path(p).read_bytes()).decode("ascii")
        content.append({"type": "image_url", "image_url": {"url": f"data:{mime};base64,{b64}"}})
    body = {
        "model": model,
        "messages": [{"role": "user", "content": content}],
        "max_tokens": max_tokens,
    }
    return extract_assistant_text(post_chat_completions(body))


def text_only_chat(user_text: str, *, max_tokens: int) -> str:
    model = os.environ.get("AXERA_VLM_MODEL") or "AXERA-TECH/Qwen3-VL-2B-Instruct"
    body = {
        "model": model,
        "messages": [{"role": "user", "content": user_text}],
        "max_tokens": max_tokens,
    }
    return extract_assistant_text(post_chat_completions(body))


def _video_system_message() -> dict | None:
    if "AXERA_VLM_SYSTEM" in os.environ:
        text = os.environ["AXERA_VLM_SYSTEM"].strip()
        if not text:
            return None
        return {"role": "system", "content": [{"type": "text", "text": text}]}
    return {"role": "system", "content": [{"type": "text", "text": "you are a helpful assistant."}]}


def _video_messages(user_content: list[dict]) -> list[dict]:
    messages: list[dict] = []
    sm = _video_system_message()
    if sm:
        messages.append(sm)
    messages.append({"role": "user", "content": user_content})
    return messages


def video_dir_chat(frames_dir: str, prompt: str, *, max_tokens: int, timeout: float) -> str:
    """Single axllm video request: image_url url is video:{abs_dir} (server reads frames from disk)."""
    model = os.environ.get("AXERA_VLM_MODEL") or "AXERA-TECH/Qwen3-VL-2B-Instruct"
    user_parts: list[dict] = [
        {"type": "image_url", "image_url": {"url": f"video:{frames_dir}"}},
        {"type": "text", "text": prompt},
    ]
    body = {
        "model": model,
        "messages": _video_messages(user_parts),
        "max_tokens": max_tokens,
    }
    return extract_assistant_text(post_chat_completions(body, timeout=timeout))


def video_base64_chat(frame_paths: list[str], prompt: str, *, max_tokens: int, timeout: float) -> str:
    """Single axllm video request: one image_url per frame with url video:data:...;base64,..."""
    model = os.environ.get("AXERA_VLM_MODEL") or "AXERA-TECH/Qwen3-VL-2B-Instruct"
    user_parts: list[dict] = []
    for p in frame_paths:
        mime = _mime_for_path(p)
        b64 = base64.standard_b64encode(Path(p).read_bytes()).decode("ascii")
        data_url = f"data:{mime};base64,{b64}"
        user_parts.append({"type": "image_url", "image_url": {"url": f"video:{data_url}"}})
    user_parts.append({"type": "text", "text": prompt})
    body = {
        "model": model,
        "messages": _video_messages(user_parts),
        "max_tokens": max_tokens,
    }
    return extract_assistant_text(post_chat_completions(body, timeout=timeout))


def cmd_image(args: argparse.Namespace) -> int:
    if args.prompt_file:
        prompt = Path(args.prompt_file).read_text(encoding="utf-8", errors="replace")
    else:
        prompt = args.prompt or "请用中文极简要列出图中主体、环境、可见文字（如有）。"
    max_toks = args.max_tokens or int(os.environ.get("AXERA_VLM_FRAME_MAX_TOKENS", "256"))
    try:
        print(one_image_chat(args.path, prompt, max_tokens=max_toks))
    except Exception as e:
        print(str(e), file=sys.stderr)
        return 1
    return 0


def cmd_video(args: argparse.Namespace) -> int:
    work = Path(args.workdir)
    frames = sorted(work.glob("frame_*.jpg"))
    if not frames:
        print("axera_vlm_http video: no frame_*.jpg in workdir", file=sys.stderr)
        return 1

    user_q = (args.query or "").strip() or "请概括视频内容。"
    mode = (os.environ.get("AXERA_VIDEO_MODE") or "base64").strip().lower()
    # Defaults sized for small KV (e.g. kv_cache_num ~1152 on edge devices): many frames → prefill OOM.
    stride = max(1, int(os.environ.get("AXERA_VIDEO_STRIDE", "2")))
    try:
        raw_max = int(os.environ.get("AXERA_VIDEO_MAX_FRAMES", str(VIDEO_MAX_FRAMES_HARD_CAP)))
    except ValueError:
        raw_max = VIDEO_MAX_FRAMES_HARD_CAP
    raw_max = max(1, raw_max)
    if raw_max > VIDEO_MAX_FRAMES_HARD_CAP:
        print(
            f"axera_vlm_http video: AXERA_VIDEO_MAX_FRAMES={raw_max} capped to {VIDEO_MAX_FRAMES_HARD_CAP}",
            file=sys.stderr,
        )
    max_frames = min(VIDEO_MAX_FRAMES_HARD_CAP, raw_max)
    selected = frames[::stride][:max_frames]
    if not selected:
        print("axera_vlm_http video: no frames after stride/max_frames", file=sys.stderr)
        return 1

    video_max = int(os.environ.get("AXERA_VLM_VIDEO_MAX_TOKENS", "512"))
    timeout = float(os.environ.get("AXERA_VLM_VIDEO_TIMEOUT", "300"))
    frame_log = os.environ.get("AXERA_VIDEO_FRAME_LOG", "").strip()
    log_line = (
        f"axera_vlm_http video: mode={mode} frames={len(selected)}/{len(frames)} "
        f"stride={stride} workdir={work.resolve()}\n"
    )
    if frame_log.lower() == "stderr":
        print(log_line, file=sys.stderr, end="", flush=True)
    elif frame_log and frame_log.lower() not in ("0", "false", "no", "off"):
        try:
            with open(frame_log, "a", encoding="utf-8") as lf:
                lf.write(log_line)
        except OSError as e:
            print(f"axera_vlm_http: cannot write frame log {frame_log!r}: {e}", file=sys.stderr)

    try:
        if mode == "base64":
            out = video_base64_chat([str(p) for p in selected], user_q, max_tokens=video_max, timeout=timeout)
        elif mode == "dir":
            # Server reads every frame image in the directory; use a subdir if workdir has extra jpgs.
            if len(selected) < len(frames):
                subset = work / "_video_subset"
                subset.mkdir(exist_ok=True)
                for old in subset.glob("frame_*.jpg"):
                    old.unlink()
                for i, p in enumerate(selected):
                    shutil.copy2(p, subset / f"frame_{i:04d}.jpg")
                dir_for_url = subset.resolve()
            else:
                dir_for_url = work.resolve()
            out = video_dir_chat(str(dir_for_url), user_q, max_tokens=video_max, timeout=timeout)
        else:
            print(f"axera_vlm_http video: unknown AXERA_VIDEO_MODE={mode!r} (use dir or base64)", file=sys.stderr)
            return 1
    except Exception as e:
        print(str(e), file=sys.stderr)
        return 1
    print(out.strip())
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="Axera VLM HTTP helper (no curl).")
    sub = ap.add_subparsers(dest="cmd", required=True)

    pi = sub.add_parser("image", help="Single image -> assistant text on stdout.")
    pi.add_argument("path", help="Image file path")
    pi.add_argument("prompt", nargs="?", default="", help="Short user prompt (optional if --prompt-file)")
    pi.add_argument("--prompt-file", help="Read prompt from file (UTF-8)")
    pi.add_argument(
        "--max-tokens",
        type=int,
        default=0,
        help="0 = use env AXERA_VLM_FRAME_MAX_TOKENS (default 256)",
    )
    pi.set_defaults(func=cmd_image)

    pv = sub.add_parser(
        "video",
        help="Frames in workdir -> single axllm video: request (dir or base64); one assistant text on stdout.",
    )
    pv.add_argument("--workdir", required=True, help="Directory containing frame_*.jpg")
    pv.add_argument("--query", default="", help="User question / focus")
    pv.set_defaults(func=cmd_video)

    args = ap.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
