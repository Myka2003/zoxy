{ config, lib, pkgs, ... }:

# zoxy 的 NixOS 模块（唯一入口）。
#
# 只依赖 nixpkgs 的 services.sunshine / services.pipewire，不依赖任何外部 flake 约定。
# 所有可调项都在 options.zoxy.* 下；**配置值通过 /etc/zoxy/config.json 传给脚本**，
# 脚本自己不认识 Nix。
let
  cfg = config.zoxy;

  zoxyPackage = cfg.package;

  configJson = (pkgs.formats.json { }).generate "zoxy-config.json" {
    user = cfg.user;
    gameRoots = cfg.gameRoots;
    targets = cfg.targets;
    stream = {
      sunshineHost = cfg.stream.sunshineHost;
      sunshineApp = cfg.stream.appName;
    };
    downloader.url = cfg.downloader.url;
  };

in
{
  options.zoxy = {
    enable = lib.mkEnableOption "zoxy 游戏下载/串流管道";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./package.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ./package.nix { }";
      description = "zoxy 包。默认用消费者自己的 nixpkgs 构建，避免版本错配。";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        运行串流会话的用户。必须设置：主机侧的 systemd 用户服务与
        `$HOME/.local/state/zoxy` 的请求/锁文件都属于这个用户。
      '';
    };

    gameRoots = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "/home/riff/Games" ];
      description = ''
        允许启动的游戏目录白名单。`zoxy-stream-session` 会用 realpath 校验
        请求里的路径必须落在这些目录内 —— 这是防止请求文件被改写成任意可执行
        路径的唯一防线，不要留空。
      '';
    };

    targets = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          type = lib.mkOption {
            type = lib.types.enum [ "local" "moonlight-client" ];
            description = "local = 本机启动；moonlight-client = 串流到另一台机器。";
          };
          label = lib.mkOption {
            type = lib.types.str;
            description = "菜单里显示的名字。";
          };
          clientHost = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "moonlight-client 必填：SSH 到客户端的地址。";
          };
          clientUser = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "moonlight-client 必填：客户端上的用户名。";
          };
          displayMode = lib.mkOption {
            type = lib.types.str;
            default = "windowed";
            description = "传给 Moonlight 的 --display-mode。";
          };
          resolution = lib.mkOption {
            type = lib.types.str;
            default = "1920x1080";
            description = "传给 Moonlight 的 --resolution。";
          };
        };
      });
      default = { };
      description = ''
        可启动目标，由 `zoxy`（TUI）读取。id 为 `local` 的条目在只有一个目标时
        会被自动选中，所以通常把本机目标命名为 local。
      '';
      example = lib.literalExpression ''
        {
          local = { type = "local"; label = "本机"; };
          living-room = {
            type = "moonlight-client";
            label = "客厅投影";
            clientHost = "mac";
            clientUser = "mingkaichen";
          };
        }
      '';
    };

    stream = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          是否在这台机器上跑串流主机端（无头 sway 会话 + Sunshine 抓屏 + 独立
          音频 sink）。纯下载/本机玩的机器可以关掉；此时仍会装好全部脚本，
          也能用 local 目标启动游戏。
        '';
      };

      sunshineHost = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "客户端 Moonlight 连接的主机名（必须是客户端能解析到的名字）。";
      };

      appName = lib.mkOption {
        type = lib.types.str;
        default = "Zoxy Session";
        description = "在 Sunshine 里注册的应用名。改这个值会和客户端已保存的应用不匹配。";
      };

      audioSink = lib.mkOption {
        type = lib.types.str;
        default = "sink-zoxy-stream";
        description = "串流专用的 PipeWire null sink；Sunshine 只抓这个 sink。";
      };
    };

    downloader.url = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:8080";
      description = ''
        qBittorrent WebUI 地址（下载工作流通过它的 API 添加/查询种子）。
        工具不自带下载器：需要你提供一个从本机免认证可达的 WebUI。
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.user != "";
        message = "zoxy.user must be set when zoxy.enable is true";
      }
      {
        assertion = cfg.gameRoots != [ ];
        message = "zoxy.gameRoots must list at least one allowed game directory";
      }
      {
        assertion = cfg.targets != { };
        message = "zoxy.targets must contain at least one target";
      }
      {
        assertion = lib.all
          (t: t.type != "moonlight-client" || (t.clientHost != null && t.clientUser != null))
          (lib.attrValues cfg.targets);
        message = "every zoxy moonlight-client target needs clientHost and clientUser";
      }
    ] ++ lib.optional cfg.stream.enable {
      assertion = config.services.sunshine.enable;
      message = "zoxy.stream.enable requires services.sunshine.enable (Sunshine 是主机端)";
    };

    # 脚本读的配置。只读挂载，脚本从不写它（grep 过：全是 -r / open(r)）。
    environment.etc."zoxy/config.json".source = configJson;

    environment.systemPackages = [ zoxyPackage ];

    # 脚本的环境变量契约只有三个（其余都有与这里一致的默认值）。
    # 放系统级而不是只塞进 unit：交互式脚本（zoxy / TUI / 请求）读的是同一份，
    # 否则改了选项只有服务变、手动跑的还是旧值。
    environment.variables = {
      ZOXY_CONFIG = "/etc/zoxy/config.json";
      ZOXY_AUDIO_SINK = cfg.stream.audioSink;
      ZOXY_DOWNLOADER_URL = cfg.downloader.url;
    };

    # ── 以下只在“这台机器是串流主机”时生效（zoxy.stream.enable）────────────

    # 串流音频走独立的 null sink，客户端只听这一路；不碰用户默认设备。
    services.pipewire.extraConfig.pipewire."10-zoxy-stream" = lib.mkIf cfg.stream.enable {
      "context.objects" = [
        {
          factory = "adapter";
          args = {
            "factory.name" = "support.null-audio-sink";
            "node.name" = cfg.stream.audioSink;
            "node.description" = "Zoxy Stream Sink";
            "media.class" = "Audio/Sink";
            "audio.position" = [ "FL" "FR" ];
            "monitor.channel-volumes" = true;
          };
        }
      ];
    };

    # 无头 Wayland 会话：Sunshine 抓它，游戏在里面跑。
    systemd.user.services.zoxy-stream-sway = lib.mkIf cfg.stream.enable {
      description = "Headless Wayland session for Zoxy game streaming";
      startLimitIntervalSec = 500;
      startLimitBurst = 5;
      wantedBy = [ "graphical-session.target" ];
      after = [ "graphical-session.target" "pipewire.service" "wireplumber.service" ];
      wants = [ "pipewire.service" "wireplumber.service" ];
      # 用户服务会在每个用户的 manager（含显示管理器 greeter）里被拉起；
      # 不限定用户的话，greeter 会话里会反复失败重启。
      unitConfig.ConditionUser = cfg.user;
      environment = {
        # 只有这个 unit 需要：它才是启动无头 sway 的那个进程
        ZOXY_SWAY_CONFIG = "${zoxyPackage.passthru.swayConfig}";
        WLR_BACKENDS = "headless,libinput";
        WLR_HEADLESS_OUTPUTS = "1";
        WLR_RENDERER = "gles2";
        WLR_LIBINPUT_NO_DEVICES = "1";
        LIBSEAT_BACKEND = "noop";
        XDG_CURRENT_DESKTOP = "sway";
        XDG_SESSION_TYPE = "wayland";
        PULSE_SINK = cfg.stream.audioSink;
      };
      serviceConfig = {
        ExecStart = "${zoxyPackage}/bin/zoxy-stream-sway";
        Restart = "on-failure";
        RestartSec = 2;
      };
    };

    services.sunshine.settings = lib.mkIf cfg.stream.enable {
      capture = "wlr";
      output_name = 0;
      audio_sink = cfg.stream.audioSink;
    };

    systemd.user.services.sunshine = lib.mkIf cfg.stream.enable {
      requires = [ "zoxy-stream-sway.service" ];
      partOf = [ "zoxy-stream-sway.service" ];
      wants = [ "pipewire.service" "wireplumber.service" ];
      after = [ "zoxy-stream-sway.service" "pipewire.service" "wireplumber.service" ];
      unitConfig.ConditionUser = cfg.user;
      environment = {
        WAYLAND_DISPLAY = "wayland-game";
        XDG_CURRENT_DESKTOP = "sway";
        XDG_SESSION_TYPE = "wayland";
        PULSE_SINK = cfg.stream.audioSink;
      };
      serviceConfig.ExecStartPre = "${zoxyPackage}/bin/zoxy-stream-wait-wayland";
    };

    # 客户端在 Moonlight 里点这个应用 → Sunshine 拉起会话脚本 → 消费请求文件。
    services.sunshine.applications = lib.mkIf cfg.stream.enable {
      apps = [
        {
          name = cfg.stream.appName;
          cmd = "${zoxyPackage}/bin/zoxy-stream-session";
          "auto-detach" = false;
          "wait-all" = true;
          "exit-timeout" = 5;
        }
      ];
    };
  };
}
