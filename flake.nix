{
  description = "Srid's NixOS / nix-darwin configuration";

  inputs = {
    # Principle inputs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    nix-darwin.url = "github:lnl7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nixos-hardware.url = "github:NixOS/nixos-hardware";
    nixos-flake.url = "github:srid/nixos-flake";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    # CI server
    sops-nix.url = "github:juspay/sops-nix/json-nested"; # https://github.com/Mic92/sops-nix/pull/328
    jenkins-nix-ci.url = "github:juspay/jenkins-nix-ci/nix-system"; # https://github.com/juspay/jenkins-nix-ci/pull/33
    # jenkins-nix-ci.url = "path:/home/srid/code/jenkins-nix-ci";
    nix-serve-ng.url = "github:aristanetworks/nix-serve-ng";

    # Software inputs
    nixos-shell.url = "github:Mic92/nixos-shell";
    nixos-vscode-server.flake = false;
    nixos-vscode-server.url = "github:nix-community/nixos-vscode-server";
    emanote.url = "github:srid/emanote";
    nixpkgs-match.url = "github:srid/nixpkgs-match";
    nuenv.url = "github:DeterminateSystems/nuenv";
    nixd.url = "github:nix-community/nixd";

    # Emacs
    emacs-overlay.url = "github:nix-community/emacs-overlay";
    nix-doom-emacs.url = "github:nix-community/nix-doom-emacs";

    # Vim & its plugins (not in nixpkgs)
    zk-nvim.url = "github:mickael-menu/zk-nvim";
    zk-nvim.flake = false;
    coc-rust-analyzer.url = "github:fannheyward/coc-rust-analyzer";
    coc-rust-analyzer.flake = false;

    # Devshell
    treefmt-nix.url = "github:numtide/treefmt-nix";
  };

  outputs = inputs@{ self, ... }:
    inputs.flake-parts.lib.mkFlake { inherit (inputs) self; } {
      systems = [ "x86_64-linux" "aarch64-darwin" ];
      imports = [
        inputs.treefmt-nix.flakeModule
        inputs.nixos-flake.flakeModule
        ./users
        ./home
        ./nixos
        ./nix-darwin
      ];

      flake = {
        # Configurations for Linux (NixOS) systems
        nixosConfigurations = {
          actual = self.nixos-flake.lib.mkLinuxSystem {
            imports = [
              self.nixosModules.default # Defined in nixos/default.nix
              inputs.sops-nix.nixosModules.sops
              ./systems/hetzner/ex101.nix
              ./nixos/server/harden.nix
              ./nixos/docker.nix
              ./nixos/lxd.nix
              ./nixos/jenkins.nix
            ];
            services.tailscale.enable = true;
            sops.defaultSopsFile = ./secrets.json;
            sops.defaultSopsFormat = "json";
          };
        };

        # Configurations for my (only) macOS machine (using nix-darwin)
        darwinConfigurations = {
          appreciate = self.nixos-flake.lib.mkMacosSystem {
            nixpkgs.hostPlatform = "aarch64-darwin";
            imports = [
              self.darwinModules.default # Defined in nix-darwin/default.nix
              ./systems/darwin.nix
            ];
          };
        };
      };

      perSystem = { self', system, pkgs, lib, config, inputs', ... }: {
        # NOTE: These overlays apply to the Nix shell only. See `nix.nix` for
        # system overlays.
        _module.args.pkgs = import inputs.nixpkgs {
          inherit system;
          overlays = [
            inputs.jenkins-nix-ci.overlay
          ];
        };

        nixos-flake.primary-inputs = [ "nixpkgs" "home-manager" "nix-darwin" "nixos-flake" ];

        treefmt.config = {
          projectRootFile = "flake.nix";
          programs.nixpkgs-fmt.enable = true;
          settings.formatter.nixpkgs-fmt.excludes =
            let
              nixosConfig = self.nixosConfigurations.actual;
              jenkinsPluginsFile = nixosConfig.config.jenkins-nix-ci.plugins-file;
            in
            [ jenkinsPluginsFile ];
        };

        packages.default = self'.packages.activate;
        devShells.default = pkgs.mkShell {
          buildInputs = [
            pkgs.nixpkgs-fmt
            pkgs.sops
            pkgs.ssh-to-age
            (
              let nixosConfig = self.nixosConfigurations.actual;
              in nixosConfig.config.jenkins-nix-ci.nix-prefetch-jenkins-plugins pkgs
            )
          ];
        };
        formatter = config.treefmt.build.wrapper;
      };
    };
}
