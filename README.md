# home-assistant-ociimage-flake

A Nix flake that provides [Home Assistant](https://www.home-assistant.io/) container images — [`ghcr.io/home-assistant/home-assistant`](https://ghcr.io/home-assistant/home-assistant), published from [home-assistant/core](https://github.com/home-assistant/core) — as hash-verified Nix packages, one per upstream release. It publishes pinned images only: nothing here defines a container service, a runtime, or a deployment, and the wiring is left to the consumer.

## Consuming

```nix
inputs.home-assistant = {
  url = "github:jgus-org/home-assistant-ociimage-flake";
  inputs.nixpkgs.follows = "nixpkgs";
  inputs.flake-lib.follows = "flake-lib";
};
```

Take the image package — `image` and `default` are the same derivation:

```nix
image = inputs.home-assistant.packages.${system}.image;
```

The `follows` lines are optional; omit them to let this flake use its own locked inputs. When you do share `flake-lib`, the shared revision must provide `mkOciImage` and, because releases are addressed by version, version-tree support. An older `flake-lib` is not an error: it ignores the version selection and silently tags the image by manifest digest instead of by release version.

Track `main` to move with upstream releases, or an exact-version branch or tag to stay put.

| Attribute                           | Purpose                                                                      |
| ----------------------------------- | ---------------------------------------------------------------------------- |
| `image`, `default`                  | The image derivation pinned on the branch you consume                        |
| `update-version`, `update-branches` | Maintainer tools that keep a branch's pin current; consumers never need them |

## The image package

The derivation output is a Skopeo `dir:` transport directory — an OCI layout holding the platform manifest, the runtime configuration, and the compressed layers exactly as published. There is no archive conversion, so the original digests are preserved on load.

The package carries:

| Attribute      | Value                                                                                   |
| -------------- | --------------------------------------------------------------------------------------- |
| `imageName`    | Source reference, including the registry host (`ghcr.io/home-assistant/home-assistant`) |
| `imageTag`     | The pinned release version                                                              |
| `imageDigest`  | The pinned platform manifest digest                                                     |
| `copyTo`       | Executable: `skopeo copy --preserve-digests dir:<output> <destination>`                 |
| `copyToPodman` | Executable: `copyTo containers-storage:<imageName>:<imageTag>`                          |

`imageTag` is the pinned release version, except on a branch seeded from a newer release whose own image has not resolved yet — that one is tagged by digest until it first resolves.

Load it into a container engine's local store — `containers-storage:` is what Podman reads:

```console
$ ${image.copyToPodman}/bin/copy-to-podman
```

`copyTo` takes any other Skopeo transport, so the same derivation can seed a local OCI layout or a directory store:

```console
$ ${image.copyTo}/bin/copy-to oci:/var/tmp/home-assistant-oci
$ ${image.copyTo}/bin/copy-to dir:/var/tmp/home-assistant-dir
```

Both wrappers invoke Skopeo with `--insecure-policy`, a registries configuration with no unqualified search, and an authentication file that contains no credentials — your own `~/.config/containers/auth.json` or Docker config is not consulted. The source reference and digest are baked in, so a copy only ever transfers the pinned content. To publish to a registry, copy with your own Skopeo invocation and credentials.

Because the output is an image directory rather than a composed image manifest, it is not a base image for image composition (`nix2container`'s `fromImage`, for example). Compose from a producer that builds an image; use this flake where you need to load a published image at a fixed digest.

## Platform support

The derivation builds on `x86_64-linux`, `aarch64-linux`, and `aarch64-darwin`, and needs no container engine — only Skopeo.

The image content is a `linux/amd64` manifest on every build host: the pinned platform is part of this flake's specification, independent of the host that builds it, so a package built on `aarch64-darwin` carries the same amd64 layers and needs emulation to run. The image reference, the platform (`os`, `arch`, optional `variant`), and any local rename of the loaded image are specified in `flake.nix`, not in the pin.

## Licence

Home Assistant Core is licensed under the Apache License 2.0; the image carries its dependencies under theirs. This flake republishes the upstream image by digest and adds no licence grant of its own.
