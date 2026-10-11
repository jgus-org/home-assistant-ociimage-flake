# home-assistant-ociimage-flake

A Nix flake that publishes [Home Assistant](https://www.home-assistant.io/) OCI images from `ghcr.io` as reproducible, hash-verified Nix derivations, one per upstream release, in a self-maintaining version tree.

Each release becomes a branch carrying its own pin; aggregates point at the newest release in their range. Nothing here defines a container service, a runtime, or a deployment — it supplies pinned images and leaves the wiring to the consumer.

## Usage

```nix
inputs.home-assistant = {
  url = "github:jgus-org/home-assistant-ociimage-flake";
  inputs.nixpkgs.follows = "nixpkgs";
  inputs.flake-utils.follows = "flake-utils";
  inputs.flake-lib.follows = "flake-lib";
};
```

Consume the image package (the flake's `default` and `image` outputs are the same package):

```nix
image = inputs.home-assistant.packages.${system}.image;
```

The `follows` declarations are optional; omit them to let this flake use its own locked inputs. When you do share them, the shared `flake-lib` revision must provide `mkOciImage`, and — because this producer is versioned — version-tree support. A `flake-lib` older than that ignores `versions` and silently tags the image by manifest digest instead of by release version.

Available packages, on `x86_64-linux`, `aarch64-linux`, and `aarch64-darwin`:

| Attribute | Purpose |
| --- | --- |
| `image`, `default` | The image derivation pinned on the current branch |
| `update-version` | Maintainer tool that refreshes the current branch's `pin.nix` |
| `update-branches` | Maintainer tool that publishes the whole version tree |

## The version tree

| Ref | Selects |
| --- | --- |
| `main` | Newest stable release |
| `v2026` | Newest stable release of that year |
| `v2026.10` | Newest stable patch release of that minor series |
| `v2026.10.1` | That exact release |
| `v2026.10.0b7` | A prerelease, named after its upstream release |

An exact version branch pins that release; an aggregate branch pins the newest release that falls in its range, and its pin is rewritten when a newer release joins the range. A prerelease advances an aggregate only if that aggregate is absent or already tracks a prerelease — `main` follows stable releases.

Track an aggregate when you want the flake to move with upstream; track an exact version when you want to stay put. Permanent pins are done via git tags, which the updater never touches.

## The image package

The derivation output is a Skopeo `dir:` transport directory — an OCI layout holding the platform manifest, the runtime configuration, and the compressed layers exactly as published. There is no archive conversion, so the original digests are preserved on load.

The package carries:

| Attribute | Value |
| --- | --- |
| `imageName` | Source reference, including the registry host (`ghcr.io/home-assistant/home-assistant`) |
| `imageTag` | The pinned release version |
| `imageDigest` | The pinned platform manifest digest |
| `copyTo` | Executable: `skopeo copy --preserve-digests dir:<output> <destination>` |
| `copyToPodman` | Executable: `copyTo containers-storage:<imageName>:<imageTag>` |

`imageTag` is the pin's version, except on a branch seeded from a newer release whose own image has not resolved yet — that one is still tagged by digest until its first successful refresh.

Load it into your container engine's local store — `containers-storage:` is what Podman reads:

```console
$ ${image.copyToPodman}/bin/copy-to-podman
```

`copyTo` takes any other Skopeo transport instead, so the same derivation can seed a local OCI layout or a directory store:

```console
$ ${image.copyTo}/bin/copy-to oci:/var/tmp/home-assistant-oci
$ ${image.copyTo}/bin/copy-to dir:/var/tmp/home-assistant-dir
```

Both wrappers invoke Skopeo with `--insecure-policy`, a registries configuration with no unqualified search, and a supplied authentication file that contains no credentials — your own `~/.config/containers/auth.json` or Docker config is not consulted. The source reference and digest are baked in, so a copy only ever transfers the pinned content. To publish to a registry, copy with your own Skopeo invocation and credentials instead.

Because the output is an image directory rather than a composed image manifest, it is not a base image for image composition (`nix2container`'s `fromImage`, for example). Compose from a producer that builds an image; use this flake where you need to load a published image at a fixed digest.

## Pinning model

Three files carry distinct responsibilities:

- `flake.nix` — the specification: which upstream is tracked. The version source, the platform (`os`, `arch`, optional `variant`), and any local rename live here, not in the pin. The image reference is derived from the branch's version, so a versioned source declares no `tag`. The pinned image platform is independent of the Nix build host; building on `aarch64-darwin` yields the same pinned `linux/amd64` image content.
- `pin.nix` — the instantiated state of one branch, written by the updater:

  ```nix
  {
    version = "…";              # the release this branch pins
    imageDigest = "sha256:…";   # platform manifest digest of that release
    imageHash = "sha256-…=";    # recursive Nix hash of the image directory
  }
  ```

  These three fields are the whole contract. The updater rewrites the file wholesale, so it carries no comments or extra fields.
- `flake.lock` — the pins for this flake's own inputs (`nixpkgs`, `flake-utils`, `flake-lib`).

The published repository commits all three on every branch, so any consumer commit resolves to the exact external resources its lock describes.

## Updating

Refresh one branch — resolve the version named on the command line (or the newest stable release, with no arguments), fetch it, and rewrite this branch's `pin.nix`:

```console
$ nix run .#update-version
$ nix run .#update-version -- 2026.10.1
```

The tool compares the resolved digest with `pin.nix` first: if the content matches and the pin already names the version being resolved, it exits without fetching. A build gate runs inside the update path, so a pin is only committed when the resulting image builds.

Publish the whole tree — discover upstream releases, seed a branch for each, refresh them, and move the aggregates:

```console
$ nix run .#update-branches -- list
$ nix run .#update-branches -- refresh --base-sha SHA --version 2026.10.1 --upstream-version 2026.10.1
$ nix run .#update-branches -- publish --base-sha SHA --versions-json JSON
```

`MINIMUM_TRACKING_VERSION` is the oldest release still maintained; older exact branches stay published as refs but stop being refreshed. It is a fixed floor rather than a rolling window, so raising it is how a rolled-off release series leaves the nightly matrix.

A scheduled GitHub Actions workflow runs that sequence daily. Manual runs need write access to the repository; dispatch `Update branches` from the Actions tab.
