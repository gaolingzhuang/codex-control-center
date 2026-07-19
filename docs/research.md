# 开源项目调研（2026-07-18）

## 结论

Codex MVP 应优先调用 Codex CLI 自带的 `app-server`，而不是读取浏览器 Cookie 或解析界面文本。官方稳定方法 `account/rateLimits/read` 返回额度窗口的已用百分比、窗口时长、重置时间、Credits 和计划类型。本机 Codex 0.145.0-alpha.18 已实测成功。

## 参考项目

| 项目 | 真实数据来源 / 可复用接口 | 许可证 | 对本项目的影响 |
|---|---|---|---|
| [CodexBar](https://github.com/steipete/CodexBar) | Codex OAuth；`codex app-server` 的 `account/rateLimits/read`；CLI/本地日志；可选 Web Dashboard。其 CLI 另提供 JSON 和 localhost HTTP。 | MIT | 验证了原生菜单栏、Provider 抽象、RPC 优先和本地历史的方向。MVP 没有复制其代码。 |
| [Codex Usage Tracker](https://github.com/douglasmonsky/codex-usage-tracker) | 扫描 `~/.codex` JSONL 日志，将聚合 token、线程、缓存等写入 SQLite；额度仅在日志带 `token_count.rate_limits` 时自动出现，否则需要手动输入。 | MIT | 适合后续“哪个任务最耗额度”的分析，不适合作为实时额度的唯一来源。 |
| [OpenUsage](https://github.com/janekbaraniewski/openusage) | Go TUI；自动发现 Codex/Claude/Cursor/Gemini 等本地工具，Codex 支持会话 token、模型拆分、credits 与 rate limits，并提供后台 tracking/hooks。 | MIT | 证明统一 Provider 模型可行；MVP 没有引入或复制其实现。 |
| [Codex Quota Monitor](https://github.com/codexquotamonitor/codex-quota-monitor) | Chrome 扩展调用 `chatgpt.com/backend-api/wham/usage`，复用已登录浏览器会话，10 分钟刷新并只把额度元数据存在 `chrome.storage.local`。 | MIT | 浏览器会话方案可用，但对原生应用需要 Cookie/钥匙串权限，因此不作为 MVP 主路径。 |

## 官方接口握手

接口定义参考 [OpenAI Codex app-server 文档](https://github.com/openai/codex/blob/main/codex-rs/app-server/README.md)。

1. 启动 `codex app-server --stdio`。
2. 发送 `initialize` 请求。
3. 发送 `initialized` 通知。
4. 发送 `account/rateLimits/read` 请求。
5. 按 `windowDurationMins` 识别短窗口和每周窗口；不能假设 `primary`/`secondary` 永远分别对应 5 小时/每周，也不能假设两个窗口都存在。

## 安全与隐私

- 不读取或保存 OAuth token、API key、浏览器 Cookie。
- 仅启动用户已经登录的本机 Codex 子进程。
- 历史文件只记录百分比、重置时间、计划类型和 Credits，不记录对话内容。
- 所有数据存放在 `~/Library/Application Support/CodexControlCenter/`。

## Apple 界面规范

- [Widgets HIG](https://developer.apple.com/design/human-interface-guidelines/widgets)：桌面组件应 glanceable、相关、简洁，采用系统字体、符号和标准间距。
- [Materials HIG](https://developer.apple.com/design/human-interface-guidelines/materials)：材质服务于层级关系；内容层避免滥用 Liquid Glass 与装饰性叠层。
- [WidgetKit foundations（WWDC26）](https://developer.apple.com/videos/play/wwdc2026/277/)：组件应优先“一眼获取信息”，更复杂操作进入应用详情。
