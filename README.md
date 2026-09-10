# zoxy

Windows 游戏在 NixOS 上的 **下载 → 启动 → 串流** 管道。

- 从 qBittorrent WebUI 拉种子、搜磁力、管理游戏源
- 用 `umu-run`（Proton）启动 exe
- 无头 sway 会话 + Sunshine + gamescope，把游戏串到 Moonlight 客户端
- 请求文件带 nonce + 时效，并且路径必须落在配置的 `gameRoots` 内

## 用（NixOS flake）

```nix
{
  inputs.zoxy.url = "github:Myka2003/zoxy";
  # 想省一份 nixpkgs：inputs.zoxy.inputs.nixpkgs.follows = "nixpkgs";

  # 在主机配置里
  imports = [ inputs.zoxy.nixosModules.default ];

  zoxy = {
    enable = true;
    user = "riff";
    gameRoots = [ "/home/riff/Games" ];
    stream = {
      enable = true;              # 串流主机端（无头 sway + Sunshine + 独立音频 sink）
      sunshineHost = "beelthost"; # 客户端能解析到的名字
    };
    targets = {
      local = { type = "local"; label = "本机"; };
      tablet = {
        type = "moonlight-client";
        label = "平板";
        clientHost = "tablet";      # 从这里 SSH 过去拉起 Moonlight
        clientUser = "riff";
      };
    };
  };
}
```

`stream.enable = false` 时只装脚本 + 写配置，不起服务：纯下载机 / 只在本机玩就用这个。

## 提供的 bin

| bin | 作用 |
|---|---|
| `zoxy` | 主入口（fzf 选游戏 → 选目标 → 本地跑或串流） |
| `zoxy-list-games` | 扫描 `gameRoots` 列出游戏 |
| `zoxy-run` | `umu-run` 启动单个 exe（`zoxy-run <exe> [args]`） |
| `zoxy-search` | 从游戏源搜磁力 |
| `zoxy-download` | 把磁力交给 qBittorrent WebUI |
| `zoxy-source-sync` | 同步游戏源列表（走 `ZOXY_SOURCE_PROXY`/`GAME_SOURCE_PROXY`） |
| `zoxy-tui` | qBittorrent 下载管理的 curses TUI |
| `zoxy-stream-request` | 写请求文件 + SSH 到客户端拉起 Moonlight |
| `zoxy-stream-session` | 主机端：校验请求 → gamescope 里启动游戏（由 Sunshine 拉起） |
| `zoxy-stream-sway` | 启动无头 sway 会话（systemd 用户服务） |
| `zoxy-stream-wait-wayland` | 等 `wayland-game` socket 就绪 |

## 环境变量契约

只有四个，其余都有默认值：

| 变量 | 默认 | 谁读 |
|---|---|---|
| `ZOXY_CONFIG` | `/etc/zoxy/config.json` | `zoxy`、`zoxy-list-games`、`zoxy-stream-request`、`zoxy-stream-session` |
| `ZOXY_AUDIO_SINK` | `sink-zoxy-stream` | `zoxy-stream-session` |
| `ZOXY_DOWNLOADER_URL` | `http://127.0.0.1:8080` | `zoxy-download`、`zoxy-tui` |
| `ZOXY_SWAY_CONFIG` | 无（必填） | `zoxy-stream-sway` |

下载器不随本项目提供：需要一个从本机**免认证**可达的 qBittorrent WebUI。

## 配置 schema（`/etc/zoxy/config.json`，由模块生成）

```json
{
  "user": "riff",
  "gameRoots": ["/home/riff/Games"],
  "targets": { "<id>": { "type": "local|moonlight-client", "label": "...", "clientHost": "...", "clientUser": "...", "displayMode": "windowed", "resolution": "1920x1080" } },
  "stream": { "sunshineHost": "...", "sunshineApp": "..." },
  "downloader": { "url": "http://127.0.0.1:8080" }
}
```

## 首次构建

仓库里**故意没有** `flake.lock`：路径输入（`path:./zoxy`）的消费者不需要它，
而独立使用时让 Nix 自己锁一次即可：

```bash
nix flake lock        # 生成 flake.lock，然后提交
```

## 开发

脚本是 `scripts/` 下的普通文件（不是 Nix 字符串），可以直接读、直接改：

```bash
nix build .#default            # 打包（writeShellApplication 会跑 shellcheck）
nix build .#checks.x86_64-linux.contract   # 真跑脚本的契约测试
```

`tests/contract.sh` 覆盖的是安全边界，不只是"文件存在"：越界路径必须被拒、过期请求必须被拒、非 `.exe` 必须被拒、`gameRoots` 必须被读取。加功能时往这里加断言，别写 grep 源码的空测试。

Python 脚本（`zoxy-tui`、`zoxy-list-games`）只用标准库，打包时 shebang 会被改写成绝对路径。
