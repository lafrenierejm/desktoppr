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
                  ./Package.resolved
                  ./Package.swift
                  ./Tests
                  ./desktoppr
                ];
              };

              nativeBuildInputs = with pkgs; [
                swift
                swiftpm
              ];

              # SwiftPM passes a macOS `--target` that differs from the wrapped compiler's
              # default, which makes cc-wrapper warn on every invocation.
              env.NIX_CC_WRAPPER_SUPPRESS_TARGET_WARNING = "1";

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

          # Runs `swift test` on a debug build.
          checks.tests = self'.packages.desktoppr.overrideAttrs (old: {
            pname = "desktoppr-tests";
            doCheck = true;
            swiftpmBuildConfig = "debug";
            swiftpmFlags = [
              "--disable-xctest" # tests use Swift Testing
              "--disable-get-task-allow-entitlement" # `codesign` isn't available in sandbox
            ];
            # `swift test` builds what it needs.
            buildPhase = ":";
            installPhase = "touch $out";
            meta = removeAttrs old.meta [ "mainProgram" ];
          });

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
              # The prebuilt binary can't find sourcekitd under Nix, so skip the rules that need it.
              swiftlint = {
                enable = true;
                package = pkgs.swiftlint;
                entry = "${pkgs.lib.getExe pkgs.swiftlint} lint --strict --disable-sourcekit --no-cache";
                types = [ "swift" ];
              };
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
            # See the comment on the package's `env`.
            env.NIX_CC_WRAPPER_SUPPRESS_TARGET_WARNING = "1";
            # SwiftLint's prebuilt binary can't find sourcekitd under Nix.
            env.SWIFTLINT_DISABLE_SOURCEKIT = "1";
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
                # XCTest isn't available under Nix, and SwiftPM can't default this flag.
                (writeShellScriptBin "run-tests" ''
                  exec swift test --disable-xctest "$@"
                '')
              ]);
          };
        };
    };
}
