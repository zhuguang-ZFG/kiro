# Kiro 本地桥接部署文档

本文档用于在 Windows 本机部署并维护 `Kiro -> AIClient2API -> CC Switch` 本地 Claude 桥接。

## 目标链路

```text
Kiro OAuth 凭证
  -> AIClient2API http://127.0.0.1:3000/v1/messages
  -> CC Switch 自定义 Claude Provider
```

推荐让 CC Switch 直接连接 `http://127.0.0.1:3000`，由 `AIClient2API` 负责消费 Kiro OAuth 凭证并暴露 Claude 兼容接口。

## 前置条件

- Windows 用户环境。
- 已安装并登录 Kiro。
- 已准备 `AIClient2API` 工程，例如：
  - `C:\Users\Administrator\AIClient2API-study`
- 已安装 Node.js，并可执行：
  - `C:\Program Files\nodejs\npm.cmd`
- 已安装 CC Switch，并能添加 Claude 兼容的本地 Provider。

## 目录约定

本文档中的默认路径如下。若机器路径不同，请在脚本参数中替换。

```text
AIClient2API 工程: C:\Users\Administrator\AIClient2API-study
Kiro/AWS SSO 缓存: C:\Users\Administrator\.aws\sso\cache
AIClient2API 配置: C:\Users\Administrator\AIClient2API-study\configs
```

## 1. 准备 AIClient2API 配置

确认 `configs/config.json` 至少包含：

```json
{
  "REQUIRED_API_KEY": "kiro-local-8f2d4b9c",
  "SERVER_PORT": 3000,
  "HOST": "127.0.0.1",
  "MODEL_PROVIDER": "claude-kiro-oauth",
  "PROXY_ENABLED_PROVIDERS": [],
  "providerFallbackChain": {
    "claude-kiro-oauth": []
  }
}
```

确认 `configs/provider_pools.json` 包含 `claude-kiro-oauth` provider。凭证路径可先写任意旧路径，后续同步脚本会自动切到最新可用凭证。

```json
{
  "claude-kiro-oauth": [
    {
      "customName": "Local Kiro OAuth",
      "KIRO_OAUTH_CREDS_FILE_PATH": "C:/Users/Administrator/.aws/sso/cache/kiro-auth-token.json",
      "uuid": "8854352e-8410-4965-b982-2048ec220b45",
      "checkModelName": null,
      "checkHealth": false,
      "isHealthy": true,
      "isDisabled": false,
      "errorCount": 0,
      "lastErrorTime": null,
      "needsRefresh": false,
      "refreshCount": 0,
      "lastErrorMessage": null,
      "scheduledRecoveryTime": null
    }
  ]
}
```

注意：`provider_pools.json` 必须是无 BOM UTF-8。仓库中的 `sync-kiro-and-start.ps1` 已按无 BOM UTF-8 写入，避免 Node.js `JSON.parse()` 报 `Unexpected token '﻿'`。

## 2. 复制自动化脚本

将仓库脚本复制到 `AIClient2API` 工程：

```powershell
Copy-Item D:\GIT\kiro\scripts\sync-kiro-and-start.ps1 C:\Users\Administrator\AIClient2API-study\scripts\sync-kiro-and-start.ps1 -Force
Copy-Item D:\GIT\kiro\scripts\watch-kiro-credentials.ps1 C:\Users\Administrator\AIClient2API-study\scripts\watch-kiro-credentials.ps1 -Force
```

## 3. 单次同步并启动

执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File C:\Users\Administrator\AIClient2API-study\scripts\sync-kiro-and-start.ps1 `
  -StartAIClient2API `
  -RestartWhenCredentialChanges `
  -VerboseLog
```

脚本会：

1. 扫描 `C:\Users\Administrator\.aws\sso\cache` 中最新可用 Kiro 凭证。
2. 更新 `configs/provider_pools.json` 的 `KIRO_OAUTH_CREDS_FILE_PATH`。
3. 清理 provider 的 unhealthy 状态。
4. 在凭证变化时重启 `AIClient2API`。

如果提示 `Access is denied`，通常是当前执行权限无法读取 Kiro/AWS SSO 缓存目录。用同一 Windows 用户重新打开 PowerShell，或以管理员权限运行一次同步脚本。

## 4. 注册开机自启 watcher

使用 Windows 用户级启动项：

```powershell
$cmd = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Users\Administrator\AIClient2API-study\scripts\watch-kiro-credentials.ps1 -PollMinutes 1'
New-ItemProperty `
  -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' `
  -Name 'AIClient2API-AutoStart' `
  -Value $cmd `
  -PropertyType String `
  -Force
```

watcher 会每 1 分钟执行一次同步脚本，并写入：

```text
C:\Users\Administrator\AIClient2API-study\logs\kiro-credential-watch.state.json
C:\Users\Administrator\AIClient2API-study\logs\kiro-credential-watch.log
```

## 5. 启动 AIClient2API

若需要手动启动：

```powershell
Set-Location C:\Users\Administrator\AIClient2API-study
npm start -- --host 127.0.0.1 --port 3000 --api-key kiro-local-8f2d4b9c --model-provider claude-kiro-oauth
```

正常监听端口：

```text
127.0.0.1:3000  Claude/OpenAI/Gemini 兼容 API
127.0.0.1:3100  AIClient2API master 管理端口
```

## 6. 配置 CC Switch

在 CC Switch 中添加或修改 Claude 兼容 Provider：

```text
Base URL: http://127.0.0.1:3000
API Key : kiro-local-8f2d4b9c
Model   : claude-sonnet-4-5
```

请求路径由客户端使用 Claude 协议访问：

```text
POST http://127.0.0.1:3000/v1/messages
```

## 7. 验证

### 验证端口

```powershell
netstat -ano -p tcp | Select-String ':3000|:3100'
```

### 验证健康接口

```powershell
Invoke-WebRequest -UseBasicParsing http://127.0.0.1:3000/health
```

注意：`/health` 只代表服务进程存活，不代表 Kiro provider 一定可用。

### 验证 Claude 请求

```powershell
Invoke-WebRequest -UseBasicParsing `
  -Method Post `
  -Uri 'http://127.0.0.1:3000/v1/messages' `
  -Headers @{
    'x-api-key' = 'kiro-local-8f2d4b9c'
    'anthropic-version' = '2023-06-01'
    'content-type' = 'application/json'
  } `
  -Body '{"model":"claude-sonnet-4-5","max_tokens":32,"messages":[{"role":"user","content":"reply OK only"}]}' `
  -TimeoutSec 90
```

成功时返回 HTTP `200`，响应体包含 Claude message JSON。

## 常见故障

### No healthy provider found

现象：

```text
No healthy provider found in pool for claude-kiro-oauth
```

处理：

1. 运行 `sync-kiro-and-start.ps1 -StartAIClient2API -RestartWhenCredentialChanges -VerboseLog`。
2. 检查 `provider_pools.json` 中 `isHealthy` 是否为 `true`。
3. 检查 `KIRO_OAUTH_CREDS_FILE_PATH` 是否指向最新 `kiro-auth-token.json`。
4. 重启 `AIClient2API`。

### provider_pools.json 解析失败

现象：

```text
Failed to load provider pools from configs/provider_pools.json
Unexpected token '﻿'
```

原因是 JSON 文件带 BOM。使用本仓库修复后的同步脚本重新写入一次，或手动转成无 BOM UTF-8。

### 同步脚本提示 Access is denied

说明当前进程无法读取：

```text
C:\Users\Administrator\.aws\sso\cache
```

处理：

1. 确认使用的是登录 Kiro 的同一个 Windows 用户。
2. 用管理员 PowerShell 运行同步脚本。
3. 检查 watcher 日志中的 `lastOutput`。

### CC Switch 能连端口但模型失败

优先直接验证 `AIClient2API`：

```text
POST http://127.0.0.1:3000/v1/messages
```

如果直接请求也失败，问题在 `AIClient2API` 或 Kiro 凭证；如果直接请求成功，再检查 CC Switch 的 Base URL、API Key 和模型名。

## 日常维护

- Kiro 重新登录后，watcher 会在下一个轮询周期同步新凭证。
- 修改 `provider_pools.json` 后需要重启 `AIClient2API` 才能稳定生效。
- 不要把真实 token 写入本仓库文档或脚本。
