{
  description = "Version-tree producer for pinned Home Assistant OCI images";

  inputs = {
    flake-lib.url = "github:jgus-org/flake-lib/v1";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs =
    {
      self,
      flake-lib,
      nixpkgs,
      ...
    }:
    let
      source = {
        imageName = "ghcr.io/home-assistant/home-assistant";
        type = "oci";
        versions = {
          owner = "home-assistant";
          repo = "core";
          type = "github";
        };
      };
    in
    flake-lib.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        orgFormatting = flake-lib.lib.mkFormatting {
          inherit self system;
        };
        pin = import ./pin.nix;
        image = flake-lib.lib.mkOciImage { inherit pin pkgs source; };
      in
      {
        checks.formatting = orgFormatting.check;
        formatter = orgFormatting.formatter;
        packages = {
          inherit image;
          default = image;
          update-branches = flake-lib.lib.mkUpdateBranches {
            inherit pkgs source;
            minimumTrackingVersion = "2026.9";
            pinSchema = "oci";
          };
          update-version = flake-lib.lib.mkUpdateVersion {
            inherit pkgs source;
          };
        };
      }
    );
}
