# Qoder CLI CN × Zed

在 Zed 的 Agent Panel 里接入 **Qoder CLI CN**（`qodercn`），走 ACP（Agent Client Protocol）。

> 非官方项目，与 Qoder / 通义云启、Zed Industries 均无隶属关系。相关商标归各自所有者。

## 为什么需要这个仓库

- `qodercn` 是**中国版独立产品**（qoder.cn），和 qoder.com 的国际版 `qoder` 不是同一个包。
- Zed 的 **ACP Registry 里只有国际版 `qoder`**（`"type": "registry"`），没有 CN 版，所以只能按 custom agent 手动配置。
- 官方文档的配置片段在 macOS / Linux 上**照抄会启动失败**，原因见「必须用绝对路径」一节。

## 前置条件

- Zed：需要支持 `"type": "custom"` 的版本（0.215.2 及更早版本不要该字段）
- Qoder CLI CN：已安装并登录（`qodercn --version` 可查版本）
- 系统：macOS / Linux / Windows；CPU：arm64 或 amd64 —— **Windows arm64 暂不支持**

## 三步接入

### 1. 安装并登录 CLI

```bash
qodercn --version   # 确认已安装
qodercn login       # 走浏览器登录，登录态会被 ACP 复用
```

安装说明见 <https://docs.qoder.cn/cli>。

### 2. 写入 Zed 配置

脚本方式（推荐，会自动探测真实路径）：

```bash
./install.sh              # 只探测环境并打印片段（默认不写文件）
./install.sh --write      # 备份后直接写入 settings.json
./install.sh --check-acp  # 额外做一次 ACP 握手验证
```

手动方式：把下面这段合并进 Zed 的 `settings.json`。

- macOS / Linux：`~/.config/zed/settings.json`（或 `$XDG_CONFIG_HOME/zed/settings.json`）
- Windows：`%APPDATA%\Zed\settings.json`

```json
{
  "agent_servers": {
    "Qoder CLI CN": {
      "type": "custom",
      "command": "/home/you/.qoder-cn/entry/qodercn",
      "args": ["--acp"]
    }
  }
}
```

`examples/` 下有两份可粘贴片段：[snippet-macos-linux.json](examples/snippet-macos-linux.json)、[snippet-windows.json](examples/snippet-windows.json)。

### 3. 验证

- Zed 会自动重载 settings，不用重启
- 打开 Agent Panel → 新建线程 → 选择 **Qoder CLI CN**
- 出问题看日志：命令面板执行 `dev: open acp logs`

## 必须用绝对路径（官方文档没提的坑）

`qodercn` 一般**不在系统默认 PATH 里**。安装脚本通常只在 `~/.bashrc` 里前置一行 PATH：

```bash
PATH="$HOME/.qoder-cn/entry:$PATH"
```

而 Zed 从桌面图标 / Dock / 应用菜单启动时**不读 `.bashrc`**，所以官方文档里 `"command": "qodercn"` 会以 `No such file or directory` 失败，线程也起不来。

先确认你机器上的情况：

```bash
env -i PATH=/usr/local/bin:/usr/bin:/bin sh -c 'command -v qodercn' || echo "NOT IN PATH"
```

如果输出 `NOT IN PATH`（很常见），就写绝对路径：

| 平台 | `command` |
| --- | --- |
| macOS / Linux | `$HOME/.qoder-cn/entry/qodercn`（展开后的绝对路径，如 `/home/you/.qoder-cn/entry/qodercn`） |
| Windows | `%USERPROFILE%\AppData\Roaming\npm\qodercn.cmd`（官方文档给的值，先跑 `where qodercn` 确认真实位置） |

> `~` 是否被 Zed 展开没有验证过，**写完整绝对路径最稳**。

## 不打开 Zed 也能验证 ACP 通道

```bash
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1,"clientCapabilities":{"fs":{"readTextFile":true,"writeTextFile":true}}}}' \
  | "$HOME/.qoder-cn/entry/qodercn" --acp
```

正常会输出一行 JSON，关键字段：

```json
{"result":{"protocolVersion":1,
  "authMethods":[{"id":"qoderclicn-login","name":"Use qoderclicn login"}],
  "agentInfo":{"name":"qoder-cli-cn","title":"Qoder CLI CN","version":"1.1.93"}}}
```

也可以用 `./install.sh --check-acp` 自动做这一步。

## 可选配置

**复用已登录状态（默认）**：ACP 进程读取 `~/.qoder-cn/.auth`，只要 CLI 登录过，Zed 里无需再登录。

**用 Personal Access Token（没跑过 `qodercn login` 时）**：

```json
"env": { "QODERCN_PERSONAL_ACCESS_TOKEN": "your_personal_access_token_here" }
```

Token 在 <https://qoder.cn/account/integrations> 获取。注意它是**明文写在 settings.json 里**的，别把配置文件提交到 git。

**跳过权限确认（等同 `--yolo`）**：

```json
"args": ["--acp", "--permission-mode", "bypass_permissions"]
```

可选值：`bypass_permissions` / `dont_ask` / `auto`；也可用 `--dangerously-skip-permissions`。

**指定模型**：

```json
"args": ["--acp", "-m", "<model-name>"]
```

可用模型：`qodercn --list-models`。

## 已验证的能力（CLI v1.1.93）

| 能力 | 状态 |
| --- | --- |
| 内置工具、Subagent | ✅ |
| MCP（stdio / SSE / Streamable HTTP） | ✅ |
| 图像输入（`promptCapabilities.image`） | ✅ |
| 嵌入上下文（`embeddedContext`） | ✅ |
| 会话 `loadSession` / `fork` / `list` / `resume` / `close` / `delete` | ✅ |
| 斜杠命令 `/init` `/memory` `/about` `/help` | ✅ |
| 文件操作与终端（由 IDE 侧提供） | ✅ |
| Windows arm64 | ❌ |

## FAQ

**选择器里没有 Qoder CLI CN？**
先跑 `./install.sh` 看能不能解析到可执行文件；再用 `dev: open acp logs` 看 spawn 错误。最常见就是 `command` 不是绝对路径。

**线程里提示要登录？**
终端里执行 `qodercn login`，然后重开线程。若想用 token，见上面的 `env` 配置。

**Zed 自己改了 settings.json？**
正常现象。在该线程里选过模型后，Zed 会往这个 agent 条目里写入 `"default_config_options": {"model": "..."}`，并可能重排字段顺序（行注释一般保留）。这不是本仓库脚本改的。

**Windows 下路径怎么写？**
先 `where qodercn`，把输出的 `.cmd` 路径填入配置，注意 JSON 里反斜杠要转义成 `\\`。

**怎么卸载？**
删掉 `agent_servers` 里的 `"Qoder CLI CN"` 块即可；`./install.sh --write` 会在写入前留一份 `settings.json.bak.*`。

**为什么不做成 Zed 扩展？**
Zed 已弃用扩展形式提供 agent，推荐路径是 ACP Registry。而 Registry 要求提交方拥有可分发产物（zip/tar 或 npx/uvx 包），`qodercn` 是闭源且由官方安装器分发，**只能由 Qoder CN 官方提交**。本仓库只是配置层方案。

## English

Qoder CLI CN (`qodercn`) speaks ACP out of the box (`qodercn --acp`) but is **not** in Zed's ACP Registry — only the international `qoder` is. Register it as a custom agent server:

```json
"agent_servers": {
  "Qoder CLI CN": {
    "type": "custom",
    "command": "/absolute/path/to/.qoder-cn/entry/qodercn",
    "args": ["--acp"]
  }
}
```

Use an **absolute** path: the installer only adds `~/.qoder-cn/entry` to `PATH` via `~/.bashrc`, which Zed never sources when launched from the desktop. Run `./install.sh` to detect the real path, verify with `./install.sh --check-acp`, then pick `Qoder CLI CN` in the Agent Panel. Auth is inherited from the CLI (`qodercn login`), or pass `QODERCN_PERSONAL_ACCESS_TOKEN` via `env`.

## License

MIT — see [LICENSE](LICENSE).
