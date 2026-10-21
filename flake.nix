{
  description = "Version-tree producer for pinned Home Assistant OCI images";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-lib = {
      url = "github:jgus-org/flake-lib/v1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      treefmt-nix,
      flake-lib,
      ...
    }:
    let
      source = {
        type = "oci";
        imageName = "ghcr.io/home-assistant/home-assistant";
        versions = {
          type = "github";
          owner = "home-assistant";
          repo = "core";
        };
      };
    in
    flake-lib.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        treefmtEval = treefmt-nix.lib.evalModule pkgs {
          projectRootFile = "flake.nix";
          programs.nixfmt.enable = true;
        };
        pin = import ./pin.nix;
        image = flake-lib.lib.mkOciImage { inherit pkgs source pin; };
      in
      {
        formatter = treefmtEval.config.build.wrapper;

        checks.formatting = treefmtEval.config.build.check self;

        packages = {
          inherit image;
          default = image;
          update-version = flake-lib.lib.mkUpdateVersion {
            inherit pkgs source;
          };
          update-branches = flake-lib.lib.mkUpdateBranches {
            minimumTrackingVersion = "2026.9";
            inherit pkgs source;
            pinSchema = "oci";
          };
        };
      }
    );
}
