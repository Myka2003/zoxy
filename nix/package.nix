{ lib, pkgs }:

# zoxy 的包本体：把 scripts/ 下的脚本装成 bin/，并声明各自的运行时依赖。
#
# 脚本是普通文件（不是 Nix 字符串），所以可以直接读、单独 lint、单独测。
# 每个 shell 脚本由 writeShellApplication 包装：自动加 shebang + `set -euo pipefail`
# + shellcheck，并把 runtimeInputs 放进 PATH。
let
  version = "0.1.0";

  # Nix 不允许路径插值（`../scripts/${bin}` 是语法错误），所以先绑成普通路径再拼字符串。
  scriptsDir = ../scripts;

  shells = {
    zoxy = with pkgs; [ coreutils findutils fzf gnugrep jq ];
    zoxy-download = with pkgs; [ curl ];
    zoxy-run = with pkgs; [ coreutils umu-launcher ];
    zoxy-search = with pkgs; [ coreutils fzf jq ];
    zoxy-source-sync = with pkgs; [ coreutils curl jq ];
    zoxy-stream-request = with pkgs; [ coreutils jq openssh util-linux ];
    zoxy-stream-session = with pkgs; [ coreutils gamescope gnugrep jq pulseaudio util-linux ];
    zoxy-stream-sway = with pkgs; [ coreutils gnugrep sway util-linux ];
    zoxy-stream-wait-wayland = with pkgs; [ coreutils ];
  };

  # Python 脚本只依赖标准库，所以把 shebang 直接指向解释器，不引入 PATH 依赖。
  pythons = [ "zoxy-list-games" "zoxy-tui" ];

  mkShell = bin: runtimeInputs: pkgs.writeShellApplication {
    name = bin;
    inherit runtimeInputs;
    text = builtins.readFile "${scriptsDir}/${bin}";
  };

  mkPython = bin: pkgs.runCommandLocal bin { } ''
    install -Dm755 "${scriptsDir}/${bin}.py" $out/bin/${bin}
    sed -i '1s|.*|#!${pkgs.python3}/bin/python3|' $out/bin/${bin}
  '';

  # 无头 sway 会话的配置（zoxy-stream-sway 通过 ZOXY_SWAY_CONFIG 读它）
  swayConfig = pkgs.writeText "zoxy-sway.conf" (builtins.readFile ../config/sway.conf);
in
pkgs.symlinkJoin {
  name = "zoxy-${version}";
  inherit version;
  paths = lib.mapAttrsToList mkShell shells ++ map mkPython pythons;

  passthru = {
    inherit swayConfig shells pythons;
  };

  meta = with lib; {
    description = "Windows 游戏在 NixOS 上的下载 → 启动 → 串流管道";
    homepage = "https://github.com/Myka2003/zoxy";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "zoxy";
  };
}
