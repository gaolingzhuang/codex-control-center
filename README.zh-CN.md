# Codex 控制中心（macOS）

[English](README.md)

一个非官方、本地优先的 macOS 菜单栏应用与原生 WidgetKit 桌面小组件，用来查看 Codex 剩余额度与各任务的 token 消耗。

## 功能

- 通过本机 Codex `app-server` 的 `account/rateLimits/read` 读取真实额度
- 展示周度剩余额度、重置时间、重置卡与结合消耗速度判断的状态
- 支持“今日 / 本周额度周期 / 全部”三种任务消耗排名
- 每条进度条按“该任务 token ÷ 当前所选周期总 token”计算
- 自动把占比很低的琐碎任务折叠为“其他低消耗任务”，可随时展开
- 提供小号、中号、大号三种原生 macOS 桌面组件
- 支持每 1、5、10、15 分钟自动刷新
- 剩余额度不高于 20% 时发送 macOS 通知，同一重置周期只提醒一次
- 在本地以 JSONL 记录额度历史
- Provider 架构已预留 Claude、Cursor、Gemini 等平台

应用不包含统计 SDK 或云端服务，也不会读取、收集或保存浏览器 Cookie、OAuth token 与 API Key。

## 系统要求

- macOS 14 或更高版本
- 已安装并登录 Codex CLI，或者已安装并登录 ChatGPT/Codex 桌面应用
- 从源码构建时需要 Xcode 16 或更高版本

## 安装发行版

1. 从仓库的 Releases 页面下载 `Codex-Control-Center-macOS.zip`。
2. 解压后把 **Codex Control Center.app** 移到“应用程序”文件夹。
3. 打开应用。它只显示在菜单栏，不会出现在 Dock。

仓库脚本生成的发行包使用本机临时签名，并未经过 Apple 公证。首次启动时，macOS 可能要求按住 Control 点击应用，选择“打开”并再次确认。请只下载你信任的 Release。

添加桌面组件：在桌面空白处按住 Control 点击，选择“编辑小组件”，搜索“Codex”，再选择需要的尺寸。

## 从源码构建

```bash
git clone <你的仓库地址>
cd codex-control-center
./scripts/check.sh
./scripts/build-app.sh
open "outputs/Codex Control Center.app"
```

构建完成后会生成：

- `outputs/Codex Control Center.app`
- `outputs/Codex-Control-Center-macOS.zip`

安装到 `/Applications`：

```bash
./scripts/install.sh
```

## 数据原理

应用启动本机已经登录的 `codex app-server --stdio`，只请求额度元数据；任务消耗则从 Codex 本地状态与会话文件聚合。任务排名与进度条分母始终使用页面当前选择的周期。

本应用生成的数据存放于：

```text
~/Library/Application Support/CodexControlCenter/
```

具体读写范围见 [PRIVACY.md](PRIVACY.md)，代码结构见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

## 开发与测试

```bash
./scripts/check.sh
```

这会运行 Swift 测试，并执行一次关闭代码签名的 Xcode Release 构建。提交代码前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)，发布版本前请阅读 [docs/RELEASING.md](docs/RELEASING.md)。

## 许可证与商标

项目源码使用 [MIT License](LICENSE)。这是独立社区项目，与 OpenAI 无隶属、赞助或背书关系。OpenAI、ChatGPT、Codex 及相关标识归其权利人所有，不属于 MIT 授权范围，详情见 [NOTICE.md](NOTICE.md)。
