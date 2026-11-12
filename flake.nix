{
  description = "desktoppr: set the desktop picture on macOS from the command line";

  inputs = {
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.zst";
    flake-parts.url = "github:hercules-ci/flake-parts";
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs:
    let
      # Single source of truth for the version: `let version = "x.y"` in Desktoppr.swift.
      version = builtins.head (
        builtins.match ''.*let version = "([^"]+)".*'' (builtins.readFile ./desktoppr/Desktoppr.swift)
      );
    in
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.git-hooks.flakeModule
        inputs.treefmt-nix.flakeModule
      ];
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      perSystem =
        {
          config,
          self',
          pkgs,
          ...
        }:
        {
          packages = {
            desktoppr = pkgs.stdenv.mkDerivation (finalAttrs: {
              pname = "desktoppr";
              inherit version;

              src = pkgs.lib.fileset.toSource {
                root = ./.;
                fileset = pkgs.lib.fileset.unions [
                  ./Package.swift
                  ./Package.resolved
                  ./desktoppr
                ];
              };

              nativeBuildInputs = with pkgs; [
                swift
                swiftpm
              ];

              # The dependencies pinned in `Package.resolved`.
              # Refresh `hash` after updating dependencies by setting to empty string and copying the hash from the error.
              swiftpmDeps = pkgs.swiftPackages.fetchSwiftPMDeps {
                inherit (finalAttrs) pname version src;
                hash = "sha256-XX+fWkYhDCMMzBfWqHCDelM21Df5ZPwHCB6IDlWCokI=";
              };

              # The swiftpm setup hook provides the configure and build phases;
              # only installation of the executable is custom.
              installPhase = ''
                runHook preInstall
                install -Dm755 "$(swiftpmBinPath)/desktoppr" $out/bin/desktoppr
                runHook postInstall
              '';

              meta = {
                description = "Command-line tool to set the macOS desktop picture";
                homepage = "https://github.com/scriptingosx/desktoppr";
                license = pkgs.lib.licenses.asl20;
                platforms = pkgs.lib.platforms.darwin;
                mainProgram = "desktoppr";
              };
            });
            default = self'.packages.desktoppr;
          };

          apps.default = {
            type = "app";
            meta.description = "Set the macOS desktop picture.";
            program = pkgs.lib.getExe self'.packages.desktoppr;
          };

          pre-commit = {
            check.enable = true;
            settings.package = pkgs.prek;
            settings.hooks = {
              convco.enable = true;
              editorconfig-checker.enable = true;
              end-of-file-fixer.enable = true;
              ripsecrets.enable = true;
              trim-trailing-whitespace.enable = true;
              treefmt.enable = true;
              typos.enable = true;
            };
          };

          treefmt.config = {
            projectRootFile = ".git/config";
            package = pkgs.treefmt;
            flakeCheck = false; # use pre-commit's check instead
            programs = {
              nixfmt.enable = true;
              swift-format.enable = true;
            };
          };

          devShells.default = pkgs.mkShell {
            # Inherit all of the pre-commit and treefmt hooks.
            inputsFrom = [
              config.pre-commit.devShell
              config.treefmt.build.devShell
            ];
            packages =
              config.pre-commit.settings.enabledPackages
              ++ (with pkgs; [
                swift
                swiftpm
                swiftPackages.sourcekit-lsp
              ]);
          };
        };
    };
}
