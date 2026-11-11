{
  description = "desktoppr: set the desktop picture on macOS from the command line";

  inputs = {
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.zst";
  };

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: rec {
        desktoppr = pkgs.stdenv.mkDerivation {
          pname = "desktoppr";
          version = "0.5";

          src = pkgs.lib.fileset.toSource {
            root = ./.;
            fileset = pkgs.lib.fileset.unions [
              ./Package.swift
              ./desktoppr
            ];
          };

          nativeBuildInputs = [
            pkgs.swift
            pkgs.swiftpm
          ];

          # Xcode substitutes these build settings into Info.plist; do the same.
          # Xcode's auto-incremented build number is not tracked here, so
          # CFBundleVersion uses the marketing version too.
          postPatch = ''
            substituteInPlace desktoppr/Info.plist \
              --replace-fail '$(MARKETING_VERSION)' "$version" \
              --replace-fail '$(CURRENT_PROJECT_VERSION)' "$version"
          '';

          # The swiftpm setup hook provides configure/build phases;
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
            platforms = systems;
            mainProgram = "desktoppr";
          };
        };
        default = desktoppr;
      });

      apps = forAllSystems (pkgs: {
        default = {
          type = "app";
          program = "${self.packages.${pkgs.system}.desktoppr}/bin/desktoppr";
        };
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell { packages = [ pkgs.swift ]; };
      });
    };
}
