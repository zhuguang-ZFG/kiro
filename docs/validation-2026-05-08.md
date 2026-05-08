# 验证记录（2026-05-08）

## 目标

验证以下链路可用，并沉淀自动化方法：

1. Kiro 凭证可被 `AIClient2API` 正常消费
2. `AIClient2API` 可通过 Claude 协议暴露本地接口
3. `CC Switch` 安装版可调用该本地接口
4. 新 Kiro 账号登录后，可通过定时轮询方式自动接入

## 本机环境

- Kiro 安装路径：`C:\Users\Administrator\AppData\Local\Programs\Kiro`
- AIClient2API 工程：`C:\Users\Administrator\AIClient2API-study`
- CC Switch 源码：`D:\GIT\cc-switch`
- CC Switch 安装版：`C:\Users\Administrator\AppData\Local\Programs\CC Switch\cc-switch.exe`

## 核心问题与结论

### 1. CC Switch 早期 502 的根因

排查后确认有两类问题：

- 一类是上游模型不兼容
- 一类是 `CC Switch` 原始 HTTP 解析路径对本地 Node 响应兼容性不足

最终通过修改 `cc-switch` 源码中的本地回环请求处理逻辑，绕过 raw parser，恢复了 `127.0.0.1`/`localhost` 的本地转发能力。

### 2. AIClient2API 上游不可用的根因

真正阻断链路的原因不是 `CC Switch` 本身，而是：

- `AIClient2API` 的 `provider_pools.json` 固定引用了一个旧的 Kiro OAuth 凭证文件
- 该旧凭证曾被标记为 `402 Payment Required - Quota Exhausted`
- 在未重置健康状态前，会持续表现为 `No healthy provider found`

在清理 unhealthy 状态并重启 `AIClient2API` 后，链路恢复。

## 已完成的修改

### AIClient2API

- 调整非流式 JSON 响应头，提升本地客户端兼容性
- 重置 `configs/provider_pools.json` 中 Kiro provider 的 unhealthy 状态
- 增加自动化脚本：
  - `scripts/sync-kiro-and-start.ps1`
  - `scripts/watch-kiro-credentials.ps1`

### CC Switch

- 修改 `src-tauri/src/proxy/hyper_client.rs`
- 对本地地址 `127.0.0.1` / `localhost` / `::1` 走 `reqwest` 路径，绕开 raw HTTP parser
- 构建 release 版并替换安装版 `cc-switch.exe`

## 验证方法

### 1. 直接验证 AIClient2API

请求：

- `POST http://127.0.0.1:3000/v1/messages`

请求头：

- `x-api-key: kiro-local-8f2d4b9c`
- `anthropic-version: 2023-06-01`

示例模型：

- `claude-sonnet-4-5`

验证结果：

- 返回成功
- 响应正文包含 `OK` / `AUTO_OK`

### 2. 验证 CC Switch 安装版

请求：

- `POST http://127.0.0.1:15721/v1/messages`

示例模型：

- `claude-sonnet-4-5`

验证结果：

- 安装版端口监听成功
- 响应正文包含 `INSTALLED_OK` / `POLL_OK`

### 3. 验证开机自启与轮询

本机使用 Windows 用户级启动项：

- 注册表项：`HKCU\Software\Microsoft\Windows\CurrentVersion\Run`
- 键名：`AIClient2API-AutoStart`

启动命令：

- `powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Users\Administrator\AIClient2API-study\scripts\watch-kiro-credentials.ps1 -PollMinutes 1`

轮询状态文件：

- `C:\Users\Administrator\AIClient2API-study\logs\kiro-credential-watch.state.json`

轮询日志文件：

- `C:\Users\Administrator\AIClient2API-study\logs\kiro-credential-watch.log`

## 自动化方案说明

### 单次同步脚本

`scripts/sync-kiro-and-start.ps1` 负责：

1. 扫描 Kiro/AWS SSO 缓存目录中的最新可用凭证
2. 更新 `AIClient2API` 的 `provider_pools.json`
3. 清理 Kiro provider 的 unhealthy 状态
4. 在凭证变更时重启 `AIClient2API`

如果某些环境下无法读取缓存目录，则脚本会：

- 保留 `provider_pools.json` 当前路径
- 继续确保 `AIClient2API` 进程可用

### 常驻 watcher

`scripts/watch-kiro-credentials.ps1` 负责：

1. 每隔 `PollMinutes` 分钟执行一次单次同步脚本
2. 记录最近一次执行状态
3. 通过命名互斥锁避免多开

## 当前状态

截至 2026-05-08，本机验证结果如下：

- `AIClient2API` 端口正常：`3000`
- `AIClient2API master` 端口正常：`3100`
- `CC Switch` 本地 Claude 代理端口正常：`15721`
- `Kiro -> AIClient2API -> CC Switch` 已跑通
- 已具备自动轮询新凭证并热切换的基础能力

## 注意事项

- 文档与脚本中未包含任何真实敏感 token
- 若在不同机器使用，需要按实际路径修改脚本参数
- 若要做到“凭证一生成立即切换”，可进一步改为文件系统事件监听；当前版本采用更稳的定时轮询
