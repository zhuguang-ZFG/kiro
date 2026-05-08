# Kiro 本地桥接验证记录

本仓库用于记录 `Kiro -> AIClient2API -> CC Switch` 本地桥接的验证结果、复现方法，以及自动化脚本。

## 内容

- `docs/validation-2026-05-08.md`
  - 本次本机验证结果
  - 复现步骤
  - 排障结论
- `scripts/sync-kiro-and-start.ps1`
  - 单次同步最新 Kiro 凭证到 `AIClient2API`
  - 必要时拉起或重启 `AIClient2API`
- `scripts/watch-kiro-credentials.ps1`
  - 常驻轮询脚本
  - 每隔几分钟检查新凭证并热切换 `AIClient2API`

## 当前结论

- 本机已验证 `CC Switch` 安装版可以经 `AIClient2API` 正常调用本地 Kiro Claude
- 已验证安装版 `CC Switch` 的本地 Claude 代理端口为 `127.0.0.1:15721`
- 已验证 `AIClient2API` 的 Claude 兼容端点为 `127.0.0.1:3000/v1/messages`
- 已实现基于 Windows 开机启动 + 轮询脚本的自动化接管方案
