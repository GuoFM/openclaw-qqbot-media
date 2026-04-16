---
name: qqbot-media
description: "QQBot 图片/语音/视频/文件收发与理解：用户发来的图片自动下载到本地；发送图片用 <qqimg>、语音 <qqvoice>、视频 <qqvideo>、文件 <qqfile>，富媒体标签须正确闭合（<qqXXX>内容</qqXXX>），否则消息无法正确解析。通过 channels.qqbot 通信时使用本技能。图/视频/语音内容理解勿用内置 video-frames；须跑 axera_vlm_image.sh、axera_vlm_video.sh、axera_asr.sh；长文/情绪等出站 TTS 用 axera_tts.sh。需 bash、python3、curl、ffmpeg。"
metadata: {"openclaw":{"emoji":"📸","requires":{"config":["channels.qqbot"],"bins":["python3","curl","ffmpeg"]}}}
---

# QQBot 图片/语音/视频/文件收发

## 给主模型的硬约束（本段优先级高于下文一切描述性文字）

**核心认知**：你是**纯文本模型**。QQ 插件传入的图片像素或视频画面不会直接作为你的多模态输入。你对「画面/视频内容」的任何回答，**唯一合法依据**是执行本技能目录下的 CLI 脚本后打印到 `stdout` 的文字。未执行脚本就输出画面结论，属于严重幻觉和错误行为。

### 你必须使用的工具形态

* **强制途径**：必须通过环境中的 **「执行终端命令 / bash / run_terminal_cmd」** 类工具执行指定的 `bash ...` 命令。
* **严禁行为**：
    * 禁止只在对话中输出命令假装执行。
    * 禁止使用 `read_file` / `cat` 读取媒体二进制文件并尝试“想象”画面。
    * 禁止使用任何非本技能指定的脚本代替 `axera_vlm_image.sh` 或 `axera_vlm_video.sh`。
    * **禁止阅读 `{baseDir}/scripts/` 下任何 `.sh`、`.py` 源码**（包括用 `read_file`/`cat` 打开）；媒体与语音的调用方式**只以本 SKILL 中的 bash 示例与环境变量为准**，无需也不应打开脚本核对实现。
* **获取路径**：优先使用下文 **「脚本路径（标准安装）」** 中的绝对路径直接执行，**不必**再 `read_file` 查找 `SKILL.md` 所在目录。仅当本机安装位置与标准不一致时，用 `read_file` 打开本技能的 `SKILL.md`，其所在目录为 `{baseDir}`。不要为「搞懂怎么调」而去读 `scripts/` 里的源码。

### 脚本路径（标准安装，可直接复制进终端）

OpenClaw 数据目录默认为 `~/.openclaw`（与 `$HOME` 相关；若你使用其他数据根目录，把前缀换成实际路径）。QQ 插件随附的本技能脚本在：

| 用途 | 绝对路径 |
| :--- | :--- |
| 图片理解 | `~/.openclaw/extensions/openclaw-qqbot/skills/qqbot-media/scripts/axera_vlm_image.sh` |
| 视频理解 | `~/.openclaw/extensions/openclaw-qqbot/skills/qqbot-media/scripts/axera_vlm_video.sh` |
| 语音入站 ASR | `~/.openclaw/extensions/openclaw-qqbot/skills/qqbot-media/scripts/axera_asr.sh` |
| 语音出站 TTS | `~/.openclaw/extensions/openclaw-qqbot/skills/qqbot-media/scripts/axera_tts.sh` |

示例（数据目录为 `/root/.openclaw` 时，将 `~` 展开为 `/root`）：`/root/.openclaw/extensions/openclaw-qqbot/skills/qqbot-media/scripts/axera_vlm_video.sh`。

### `{baseDir}` 与命令中的占位符

* **`{baseDir}`**：本技能 `SKILL.md` 所在目录（与上表 `.../skills/qqbot-media` 等价）。非标准安装时用此占位符。
* **占位符替换**：下文命令中的 `ABS_IMG` / `ABS_VIDEO` / `ABS_AUDIO` / `ABS_OUT` 必须在执行时替换为上下文中的**真实绝对路径**（必须以 `/` 开头）。

### 何时必须跑 CLI（触发即执行，无例外）

当满足以下任一条件时，**在对用户作答（或发送 `<qqvoice>`）之前，必须先跑对应命令**。
*注：如果用户仅仅是转发媒体，没有要求你识别或回复内容，则无需触发 CLI。*

| 媒体类型 | 触发判定条件 | 执行动作 |
| :--- | :--- | :--- |
| **图片理解** | 上下文出现图片附件、`MediaPaths`、`MediaPath` 或包含图片后缀（`.jpg/.png/.webp`等）的路径，**且**用户提问涉及画面、图中文字、物体等内容。 | 执行 `axera_vlm_image.sh` |
| **视频理解** | 上下文出现类似 `[附件: ...mp4/mkv等]` 的路径，**且**用户要求概括、识别或询问视频内容。 | 执行 `axera_vlm_video.sh` |
| **语音理解 (ASR)** | 上下文出现 `QQVoiceAttachmentPaths`、「语音附件」、「录音」字段或明示发来语音消息，且列出了本地音频路径，**且**需要理解用户的口述内容。 | 执行 `axera_asr.sh` |
| **语音回复 (TTS)** | 拟回复内容满足以下任一：<br>1. 正文**超过 100 字**（非纯代码/列表类技术说明）。<br>2. 以致歉、安慰、赞赏为主的情绪化表达。<br>3. 用户明确要求“语音回复/读出来/发语音”。<br>4. 包含唱、念诗、配音或模仿语气等场景。 | 在写入 `<qqvoice>` 标签前执行 `axera_tts.sh` |

### 必须复制的命令（把 `ABS_*` 换成真实绝对路径）

**1. 图片理解**（每张图各跑一次；路径可用上表 `axera_vlm_image.sh` 全路径）：
```bash
bash ~/.openclaw/extensions/openclaw-qqbot/skills/qqbot-media/scripts/axera_vlm_image.sh "ABS_IMG" "用中文简要回答用户的问题；若用户未具体问题则客观描述主体与可见文字。"
```
（等价：`bash "{baseDir}/scripts/axera_vlm_image.sh" ...`）

**2. 视频理解**（每个视频跑一次；单次推理**最多 8 帧**，见下文环境变量）：

```bash
bash ~/.openclaw/extensions/openclaw-qqbot/skills/qqbot-media/scripts/axera_vlm_video.sh "ABS_VIDEO" "用中文概括视频并直接回答用户问题。"
```
（等价：`bash "{baseDir}/scripts/axera_vlm_video.sh" ...`）

> **注意**：图/视频的识别结果**全盘依赖 stdout 全文**，你可以复述或压缩或总结扩展，但**严禁编造** stdout 中未出现的内容。视频脚本在终端输出**一段** axllm 对整段视频（`video:` 协议）的识别结果。

**3. 语音入站 (ASR)**：

```bash
bash ~/.openclaw/extensions/openclaw-qqbot/skills/qqbot-media/scripts/axera_asr.sh "ABS_AUDIO"
```
（等价：`bash "{baseDir}/scripts/axera_asr.sh" ...`）

> **注意**：以 `stdout` 打印的转写文本为准。插件注入的 `asr_refer_text` 仅作为 CLI 失败时的兜底参考。

### 执行顺序（违反即错）

1.  **判定条件**：识别上下文中是否触发了图片/视频/语音的理解需求，或你的回复是否满足语音播报 (TTS) 条件。
2.  **终端执行**：调用终端工具执行上述对应的 Bash 命令，并**等待运行结束**。
3.  **获取结果并作答**：**仅在成功拿到 `stdout` 后**，再撰写对用户的回复。禁止跳过第二步直接输出盲猜内容。

### 明确禁止清单

1.  **禁止盲猜**：未执行 VLM 脚本前，绝对不许对媒体画面下定论（包括使用“推测是…”、“好像是…”等话术）。
2.  **禁止伪造理解**：不能仅仅用 `<qqimg>` 抽帧发给用户，就宣称自己已经完成了“视频理解”。
3.  **禁止越权自写请求**：不许用 `read` 或自写 Python 脚本去调其他 HTTP 客户端替代本目录下的官方脚本。
4.  **禁止虚假声称**：不要在纯文本配置下对用户说“我已经看到你发的图了”，你只能说“根据识别结果...”。
5.  **禁止忽略语音原文件**：只要有语音路径且需要理解，必须跑 `axera_asr.sh`，不能单纯依赖低置信度的 `asr_refer_text`。

### 图 / 视频脚本用法（只看本节；勿读 `scripts/` 源码）

  * **`axera_vlm_image.sh`**：第 1 参数为图片绝对路径，第 2 参数为提示词（可省略时用默认短提示）。**成功时 `stdout` 整段即为识别结果**，stderr 为错误信息。
  * **`axera_vlm_video.sh`**：第 1 参数为视频绝对路径，第 2 参数为提示词（可省略时用默认概括类提示）。脚本会均匀抽取多帧并在后台完成一次「视频」推理；**单次请求送入模型的帧数硬上限为 8**（不可超过），可用 `AXERA_VIDEO_STRIDE` 在 8 帧以内再稀疏采样。**成功时 `stdout` 仅一段中文（或模型语言）描述**，stderr 为错误信息。默认在远端服务不可读本机临时目录时，应使用 **`AXERA_VIDEO_MODE=base64`**（默认即此）；仅当 VLM 服务与抽帧环境**共享同一可访问文件系统**时，可设 **`AXERA_VIDEO_MODE=dir`**。抽帧与超时等**一律用下文环境变量控制**，不要打开 `.sh` 去查默认值。
  * **KV / 显存**：每帧都会占大量 **prefill token**（base64 模式尤甚）。若仍出现 `input_num_token` 大于 `kv_cache_num` / `SetKVCache failed`，在**至多 8 帧**前提下增大 `AXERA_VIDEO_STRIDE`、缩短用户提示词，或略减 `AXERA_VIDEO_FRAMES`（落盘帧数，仍 ≤8）。
  * **视频调试**：若需在终端或文件里留一行摘要（模式、选中帧数等），设置 `AXERA_VIDEO_FRAME_LOG=stderr` 或指向某日志文件路径。

### 环境变量与默认 ASR/TTS URL（覆盖用）

在执行上文的 `bash ...` 前，由宿主环境注入即可；**以变量名为准，勿读脚本确认**。

  * **VLM 相关**：`AXERA_VLM_BASE`, `AXERA_VLM_MODEL`, `AXERA_API_KEY`, `AXERA_VLM_FRAME_MAX_TOKENS`（图）；视频另见 `AXERA_VIDEO_MODE`（`base64`|`dir`）, `AXERA_VIDEO_FRAMES`（落盘帧数，默认 8，**与 `AXERA_VIDEO_MAX_FRAMES` 均不得超过 8**）, `AXERA_VIDEO_STRIDE`（默认 2，在上限内稀疏采样）, `AXERA_VIDEO_MAX_FRAMES`（默认 8，**硬上限 8**，更大值会被截断）, `AXERA_VLM_VIDEO_MAX_TOKENS`, `AXERA_VLM_VIDEO_TIMEOUT`, `AXERA_VLM_SYSTEM`（设为空字符串可去掉 system 消息）, `AXERA_VIDEO_FRAME_LOG`。
  * **ASR 相关**：默认 URL `http://10.126.35.203:8090/v1/audio/transcriptions`。
* **TTS 相关**：默认 URL `http://172.17.0.1:8080/v1/audio/speech`。
  * **自动语种检测**：按 **TTS** 小节参数调用 `axera_tts.sh` 时，合成请求会按待合成正文**自动判定**语言码（`instructions`），**不**再靠单独的环境变量切换语种。
  * **判定规则**（供你写回复文本时心里有数，仍勿读 `.sh`）：优先平/片假名 → `ja`；其次汉字 → `zh`；否则若含拉丁字母 → `en`；其他 → `zh`。
  * **纯音素模式**：若仅使用 `AXERA_TTS_PHONEMES` 且无文本正文，对音素串使用与上相同的语种判定规则。
  * **API Key**：`AXERA_API_KEY`。

### 文字 vs 语音回复（不要永远只打字）

  * **什么时候必须发语音**：满足前文【何时必须跑 CLI】表格中“语音回复 (TTS)”条件的场景（长文、情绪安抚、指令要求、才艺展示等）。
  * **什么时候发纯文字**：简短说明、代码块、列表、链接、需要用户复制的信息。
  * **混合策略**：如果用户用语音问你，或者语境极度偏向日常对话，建议采用“**文字摘要 + `<qqvoice>` 语音完整播报**”的形式，避免干瘪的纯文字。
  * **先合成再发送**：发 `<qqvoice>` 前，必须先通过 `axera_tts.sh` 拿到**本地绝对路径**，严禁编造路径。

### 语音回复与 TTS（出站）

**终端执行命令**：

```bash
bash ~/.openclaw/extensions/openclaw-qqbot/skills/qqbot-media/scripts/axera_tts.sh "ABS_OUT" "要说的中文或台词"
```
（等价：`bash "{baseDir}/scripts/axera_tts.sh" ...`）

  * **参数**：
      * `ABS_OUT`：输出的音频绝对路径（建议指定带扩展名的名称，如 `/tmp/reply.wav`）。
      * `"文本"`：需要合成的声音内容（多段文本用空格隔开时会合并为一次合成）。
  * **输出 (`stdout`)**：**仅输出一行**实际生成的音频绝对路径。请将此路径原样包裹在 `<qqvoice>` 标签内发送。
  * **其他用法**：支持 stdin 模式（如 `echo "文本" | bash ...`）。
  * **语言**：每次调用均按待合成字符串（无正文则按 `AXERA_TTS_PHONEMES`）自动选 `en`/`zh`/`ja` 写入 `instructions`，规则同上；不设环境变量覆盖。

### CLI 规格：入站语音 `axera_asr.sh`（必读，避免服务端 load wav 失败）

QQ 下载的语音常为 `.bin` 或 SILK，不能当普通 WAV 直传。**用法**：只执行下述一条命令；脚本会在本地把输入转成 **16 kHz 单声道 PCM WAV** 再请求 ASR（细节以成功 `stdout` 为准，**勿打开脚本阅读**）。

**终端调用**：

```bash
bash ~/.openclaw/extensions/openclaw-qqbot/skills/qqbot-media/scripts/axera_asr.sh "ABS_AUDIO"
```
（等价：`bash "{baseDir}/scripts/axera_asr.sh" ...`）

  * **输出 (`stdout`)**：仅输出转写的纯文本。
  * **错误 (`stderr`)**：输出转码/请求错误，并以非零状态码退出。
  * **依赖项**：宿主机必须装有 `ffmpeg` 和 `ffprobe`。

-----

## 速查表（与上文硬约束一致）

| 处理场景 | 执行的 Bash 命令（`~/.openclaw/extensions/openclaw-qqbot/skills/qqbot-media/scripts/` 下对应 `.sh`） |
| :--- | :--- |
| **图片理解** | `bash ~/.openclaw/extensions/openclaw-qqbot/skills/qqbot-media/scripts/axera_vlm_image.sh "图片绝对路径" "提示词"` |
| **视频理解** | `bash ~/.openclaw/extensions/openclaw-qqbot/skills/qqbot-media/scripts/axera_vlm_video.sh "视频绝对路径" "提示词"`（单次 ≤8 帧） |
| **语音转文字 (ASR)** | `bash ~/.openclaw/extensions/openclaw-qqbot/skills/qqbot-media/scripts/axera_asr.sh "语音绝对路径"` |
| **文字转语音 (TTS)** | `bash ~/.openclaw/extensions/openclaw-qqbot/skills/qqbot-media/scripts/axera_tts.sh "输出路径.wav" "要说的文本"` <br>*(完成后提取 stdout 路径使用 `<qqvoice>` 发送)* |

-----

## 标签速查（直接复制使用）

标签拼写必须严格遵循下表，仅支持这 4 个标签，支持 `</标签>` 闭合方式。**必须单独成行或前后留空。**

| 媒体类型 | 标签语法 | 示例 |
| :--- | :--- | :--- |
| **图片** | `<qqimg>绝对路径或URL</qqimg>` | `<qqimg>/tmp/pic.jpg</qqimg>` |
| **语音** | `<qqvoice>绝对路径</qqvoice>` | `<qqvoice>/tmp/voice.wav</qqvoice>` |
| **视频** | `<qqvideo>绝对路径或URL</qqvideo>` | `<qqvideo>/tmp/video.mp4</qqvideo>` |
| **文件** | `<qqfile>绝对路径或URL</qqfile>` | `<qqfile>/tmp/doc.pdf</qqfile>` |

## ⚠️ 重要：你有能力发送本地图片！

**只要使用 `<qqimg>` 标签包裹图片的绝对路径，你就能发送任何本地图片！系统会自动拦截并处理文件的读取与发送。**

  * **❌ 绝对禁止**回答：“我无法发送本地图片”或“受限于技术原因我发不了”。
  * **✅ 正确做法**：直接在回复中写 `<qqimg>/绝对路径.jpg</qqimg>`。

-----

## 📸 发送图片（推荐方式：`<qqimg>` 标签）

### ✅ 发送本地图片示例

当用户要求“看看那张图”、“发送图片”时，直接输出：

```text
这是你要的图片：
<qqimg>/Users/xxx/images/photo.jpg</qqimg>
```

### ✅ 发送之前生成/创建的图片

如果你通过其他工具（如画图、代码生成）创建了图片，并且知道输出的绝对路径：

```text
好的，这是刚才生成的图片：
<qqimg>/Users/xxx/Pictures/openclaw-drawings/drawing_xxx.png</qqimg>
```

### ✅ 发送网络图片示例

支持的图片格式包括：jpg, jpeg, png, gif, webp, bmp。

```text
这是网络上的图片：
<qqimg>[https://example.com/image.png](https://example.com/image.png)</qqimg>
```

## 接收图片

用户发送的图片会自动下载到本地，上下文中的【图片附件】或相应字段会提供绝对路径。

  * **如果要理解图片**：严格遵守硬约束，对每条路径跑 `axera_vlm_image.sh` 后再作答。
  * **如果只是转发图片**：直接使用 `<qqimg>` 标签原路发送，无需跑 VLM 脚本。

## 接收视频（理解 ≠ 发 `<qqimg>` 预览）

视频通常以 `[附件: /绝对路径/xxx.mp4]` 的格式出现在上下文中。

  * **如果要理解视频**：必须跑 `axera_vlm_video.sh` 脚本，以 stdout 为唯一依据作答。
  * **严禁替代**：**绝对不能**自己抽一帧图用 `<qqimg>` 发送，然后谎称自己看懂了视频。
  * **仅预览需求**：只有在用户**明确**说“给我抽帧预览”时，你才可以发 `<qqimg>`；若用户同时询问内容，依然必须跑 VLM。

## 接收语音

上下文出现 `QQVoiceAttachmentPaths` 等字段时，代表有本地语音待处理。

  * QQ 的语音文件多为变种 SILK (`.bin`)。
  * **必须遵守**：使用终端工具跑上文 **CLI 规格**中的 `axera_asr.sh` 命令，等待结束并仅以 **stdout** 转写文本作答（不要为确认转码细节去读 `scripts/`）。
  * 只有当 CLI 失败或崩溃时，才参考平台透传的低置信度文本 `asr_refer_text` 作为兜底。若涉及金额、时间等敏感信息，务必向用户追问确认。

## 发送语音

使用 `<qqvoice>` 标签包裹**已经存在的、本地合法的音频绝对路径**。
若要语音回复用户，标准流程为：

1.  跑 `axera_tts.sh` 生成语音文件。
2.  将生成的绝对路径用 `<qqvoice>/tmp/...wav</qqvoice>` 发送。

## 发送视频

使用 `<qqvideo>` 包裹本地绝对路径或公网 URL。

```text
<qqvideo>/path/to/video.mp4</qqvideo>
<qqvideo>[https://example.com/video.mp4](https://example.com/video.mp4)</qqvideo>
```

## 发送文件

使用 `<qqfile>` 包裹本地绝对路径或网络 URL。

```text
这是你要的文件：
<qqfile>/Users/xxx/document.pdf</qqfile>
```

### 📝 标签说明

*(有关标签的具体使用准则，请参阅下方的注意事项)*

## ⚠️ 关键注意事项（必须遵守）

1.  **强制绝对路径**：标签内的路径必须是系统绝对路径（以 `/` 开头），**禁止使用相对路径**（如 `./pic.jpg`）。（通常在 `~/.openclaw/workspace/` 目录下）。
2.  **标签语法完整**：包含 `<` 和 `>` 以及正确的闭合（如 `</qqimg>`）。
3.  **独立排版**：标签必须单独占一行，或前后至少有空格，不要将其死死嵌入句子中。
4.  **文件大小限制**：无论图片、语音、视频还是文件，上传大小极限为 **20MB**。

## 规则

  * **禁止使用其他 Message Tool** 发送图片/文件，只需在纯文本回复中打出 XML 标签即可，框架会自动拦截并处理。
  * **禁止拒绝服务**：永远不要说“无法访问/发送之前的图片/文件”。
  * **正文共存**：标签之外的普通文字会作为消息正文与媒体一并发送。
  * **多媒体支持**：允许在一次回复中包含多个不同的媒体标签（如图文混排）。
  * **尊重配置**：请以当前会话的能力说明为准，如果未启用语音模块，不要强行发送。

## 🚫 错误示例（不要这样做）

  * ❌ **错误**：回答“我无法发送本地图片”。
  * ❌ **错误**：回答“受限于技术限制/机器人通道配置，我无法直接发送图片”。
  * ❌ **错误**：光秃秃地打出路径 `/root/pic.jpg`，却不用 `<qqimg>` 标签包裹。
  * ❌ **错误（视频）**：回答“我无法直接观看视频”，然后自行抽帧发图敷衍，**从未执行** `axera_vlm_video.sh`。
  * ❌ **错误（视频）**：把给用户的截图预览当成“视频内容理解”的输出。
  * ❌ **错误（不跑CLI瞎编）**：根本没调用 `bash axera_vlm_...` 就在回复里煞有介事地描述画面细节。
  * ❌ **错误（忽略录音）**：用户明明发了语音附件跟你聊天，你却因为没跑 ASR，直接回复“你发的是什么我听不到”。

## 🔤 告知路径信息（不发送图片）

如果你仅仅是想告诉用户文件被存在了哪里，而**不想触发发送动作**，请作为纯文本或代码块输出，**不要带标签**：

```text
图片已保存在：/Users/xxx/images/photo.jpg
或：
图片已保存在：`/Users/xxx/images/photo.jpg`
```

## 📋 高级选项：JSON 结构化载荷

若需要非常精细的控制（如同时发送图片和特定摘要图注），可以使用特殊的 `QQBOT_PAYLOAD` JSON 格式：

```json
QQBOT_PAYLOAD:
{
  "type": "media",
  "mediaType": "image",
  "source": "file",
  "path": "/path/to/image.jpg",
  "caption": "图片描述（可选）"
}
```

### JSON 字段说明

| 字段 | 类型 | 必填 | 说明 |
| :--- | :--- | :--- | :--- |
| `type` | string | ✅ | 固定为 `"media"` |
| `mediaType` | string | ✅ | 媒体类型：`"image"`、`"voice"`、`"video"`、`"file"` |
| `source` | string | ✅ | 来源：`"file"` (本地文件) 或 `"url"` (网络资源) |
| `path` | string | ✅ | 媒体的绝对路径或完整 URL |
| `caption` | string | ❌ | （可选）媒体描述，将作为单独的消息文本发出 |

> 💡 **提示**：对于日常 99% 的多媒体收发场景，强烈建议直接使用 `<qqimg>` 等简明标签。

## 🎯 快速参考

| 需求场景 | 最优使用方式 |
| :--- | :--- |
| **发送本地图片** | `<qqimg>/path/to/image.jpg</qqimg>` |
| **发送网络图片** | `<qqimg>https://example.com/image.png</qqimg>` |
| **发送多图/图文** | 混合书写文字与多个 `<qqimg>` 标签 |
| **只告知路径位置** | 直接书写纯文本路径（如：`/tmp/1.jpg`） |

```
```