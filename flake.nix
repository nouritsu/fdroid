{
  description = "nouritsu's F-Droid repo: the apps' signed releases as one repo at fdroid.nouritsu.com";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = {
    self,
    nixpkgs,
  }: let
    inherit (nixpkgs) lib;
    # fdroidserver and the Android tools it calls run here, like the apps' own builds.
    forAllSystems = f: lib.genAttrs ["x86_64-linux"] (system: f nixpkgs.legacyPackages.${system});
  in {
    packages = forAllSystems (pkgs: {
      fdroid-repo = pkgs.callPackage ./nix/fdroid-repo.nix {};
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.fdroid-repo;
    });

    apps = forAllSystems (pkgs: {
      fdroid-repo = {
        type = "app";
        program = lib.getExe self.packages.${pkgs.stdenv.hostPlatform.system}.fdroid-repo;
        meta.description = "Build the F-Droid repo from the apps' signed APKs into out/fdroid";
      };
    });

    # alejandra over every .nix file. treefmt supplies the paths: `nix fmt` passes none,
    # which bare alejandra would read as "format stdin".
    formatter = forAllSystems (pkgs:
      pkgs.treefmt.withConfig {
        name = "alejandra-tree";
        runtimeInputs = [pkgs.alejandra];
        settings = {
          tree-root-file = "flake.nix";
          on-unmatched = "info";
          formatter.alejandra = {
            command = "alejandra";
            options = ["--quiet"];
            includes = ["*.nix"];
          };
        };
      });

    checks = forAllSystems (pkgs: let
      system = pkgs.stdenv.hostPlatform.system;
    in {
      formatting = self.formatter.${system}.check (lib.fileset.toSource {
        root = ./.;
        fileset = lib.fileset.fileFilter (file: file.hasExt "nix") ./.;
      });
      inherit (self.packages.${system}) fdroid-repo;
    });
  };
}
