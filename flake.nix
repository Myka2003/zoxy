{
  description = "zoxy — Windows 游戏在 NixOS 上的下载 → 启动 → 串流管道";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" ];
      forAll = f: nixpkgs.lib.genAttrs systems (system: f system nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAll (system: pkgs: rec {
        zoxy = pkgs.callPackage ./nix/package.nix { };
        default = zoxy;
      });

      # 唯一的模块入口。使用者只需要：
      #   imports = [ inputs.zoxy.nixosModules.default ];
      #   zoxy = { enable = true; user = "riff"; gameRoots = [ "/home/riff/Games" ]; };
      nixosModules.default = import ./nix/module.nix;
      nixosModules.zoxy = self.nixosModules.default;

      checks = forAll (system: pkgs: {
        package = self.packages.${system}.zoxy;

        # 契约测试：请求文件格式、配置 schema、脚本可执行性。
        # 这些测试会真的跑脚本，不只是 grep 源码。
        contract = pkgs.runCommand "zoxy-contract" {
          nativeBuildInputs = [ pkgs.bash pkgs.jq pkgs.python3 (self.packages.${system}.zoxy) ];
        } ''
          bash ${./tests/contract.sh} ${self.packages.${system}.zoxy}
          touch $out
        '';
      });
    };
}
