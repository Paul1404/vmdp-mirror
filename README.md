# vmdp-mirror

A fast GitHub mirror of the **SUSE Virtual Machine Driver Pack (VMDP)** ISO —
the WHQL-signed Windows guest drivers for KVM / Harvester / KubeVirt.

SUSE ships the ISO inside a scratch container image
(`registry.suse.com/suse/vmdp/vmdp:latest`) and also on `sources.suse.com`,
which is *extremely* slow. This repo polls the upstream image daily and, when a
new version appears, extracts the ISO and republishes it as a GitHub Release
asset — so you can pull it at GitHub speeds instead.

## Download

**Latest (recommended):**

```sh
curl -fL -o vmdp.iso "$(curl -fsSL https://api.github.com/repos/Paul1404/vmdp-mirror/releases/latest | grep -o 'https://[^"]*\.iso')"
```

…or with `wget`:

```sh
wget -O vmdp.iso "$(curl -fsSL https://api.github.com/repos/Paul1404/vmdp-mirror/releases/latest | grep -o 'https://[^"]*\.iso')"
```

The command resolves the current release's ISO asset and downloads it, so it
keeps working across version bumps without editing the URL.

**Pinned to a specific version** (browse [Releases](https://github.com/Paul1404/vmdp-mirror/releases) for tags):

```sh
wget https://github.com/Paul1404/vmdp-mirror/releases/download/v2.5.5.7.1/VMDP-WIN-2.5.5.iso
```

### Verify the download

Each release ships a `*.iso.sha256` alongside the ISO:

```sh
curl -fLO "$(curl -fsSL https://api.github.com/repos/Paul1404/vmdp-mirror/releases/latest | grep -o 'https://[^"]*\.iso')"
curl -fLO "$(curl -fsSL https://api.github.com/repos/Paul1404/vmdp-mirror/releases/latest | grep -o 'https://[^"]*\.iso\.sha256')"
sha256sum -c VMDP-WIN-*.iso.sha256
```

## How it works

[`scripts/mirror.sh`](scripts/mirror.sh), run daily by
[the workflow](.github/workflows/mirror.yml):

1. **Detect** — fetches an anonymous registry token, reads the image manifest,
   and pulls the ~8 KB config blob to read the
   `org.opencontainers.image.version` label. No large download just to check.
2. **Skip** — if a release tagged `v<version>` already exists, it stops there.
   Same version ⇒ no-op.
3. **Mirror** — otherwise it downloads the single image layer (~24 MB gzip),
   extracts `disk/VMDP-WIN-*.iso`, and publishes it plus a SHA256 checksum as a
   new GitHub Release marked `latest`.

It uses only `curl`, `jq`, `tar`, and `gh` — no Docker daemon and no registry
credentials. The only token in play is the workflow's automatic `GITHUB_TOKEN`.

### Run it yourself

```sh
./scripts/mirror.sh --check            # print the current upstream version
./scripts/mirror.sh --no-publish ./out # download + extract the ISO locally
GH_TOKEN=$(gh auth token) ./scripts/mirror.sh   # detect + publish if new
```

## Notes

- The ISO is **never committed** to the repo — only attached to releases.
- This is an unofficial mirror provided for convenience. VMDP is published by
  SUSE; the canonical source is <https://www.suse.com/download/suse-vmdp/>.
  All trademarks belong to their respective owners.

## License

The mirroring tooling in this repo is [MIT](LICENSE) licensed. The VMDP ISO
itself is distributed under SUSE's own terms.
