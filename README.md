# openclaw-qqbot-media

OpenClaw 技能包：**QQBot 图片 / 语音 / 视频 / 文件** 收发与理解（`channels.qqbot`）。

- 主说明与模型约束见仓库根目录的 [`SKILL.md`](./SKILL.md)。
- 脚本位于 [`scripts/`](./scripts/)（VLM 图/视频、ASR、TTS）。

## 依赖

- `bash`、`python3`、`curl`、`ffmpeg`
- OpenClaw 中已配置 `channels.qqbot`

## 安装

将本目录作为 OpenClaw 的 `qqbot-media` 技能放到扩展/技能路径下（与你在 OpenClaw 中配置的 skills 目录一致即可）。

## 许可证

本仓库以 **MIT** 许可发布，全文见根目录 [`LICENSE`](./LICENSE)。

- 上游版权：`sliverp`、`Tencent Connect`（见 `LICENSE`）。
- 本仓库含在此基础上由 **GuoFM** 维护的修改与补充；再分发时请保留 `LICENSE` 中的版权声明与许可全文。

使用 QQ / 机器人等平台能力时，还须遵守腾讯及相关平台的开发者协议与服务条款（与开源许可证是不同层面的约束）。
