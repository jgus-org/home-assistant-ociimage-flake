{
  description = "Version-tree producer for pinned Home Assistant OCI images";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    flake-utils.url = "github:numtide/flake-utils";
    flake-lib = {
      url = "github:jgus-org/flake-lib/v1";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
  };

  outputs =
    {
      nixpkgs,
      flake-utils,
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
    flake-utils.lib.eachSystem
      [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ]
      (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          pin = import ./pin.nix;
          image = flake-lib.lib.mkOciImage { inherit pkgs source pin; };
        in
        {
          packages = {
            inherit image;
            default = image;
            update-version = flake-lib.lib.mkUpdateVersion {
              inherit pkgs source;
              buildAttr = "image";
              verification = "build";
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
