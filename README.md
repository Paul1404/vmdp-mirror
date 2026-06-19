# vmdp-mirror

A fast GitHub mirror of the **SUSE Virtual Machine Driver Pack (VMDP)** ISO —
the WHQL-signed Windows guest drivers for KVM / Harvester / KubeVirt.

SUSE ships the ISO inside a scratch container image
(`registry.suse.com/suse/vmdp/vmdp:latest`) and also on `sources.suse.com`,
which is *extremely* slow. This repo polls the upstream image daily and, when a
new version appears, extracts the ISO and republishes it as a GitHub Release
asset — so you can pull it at GitHub speeds instead.

## Download

Each command resolves the current release's ISO and downloads it under its
real, versioned name (e.g. `VMDP-WIN-2.5.5.iso`) — so it keeps working across
version bumps without editing the URL.

**Linux / macOS** — `curl` (capital `-O` keeps the upstream filename):

```sh
curl -fLO "$(curl -fsSL https://api.github.com/repos/Paul1404/vmdp-mirror/releases/latest | grep -oE 'https://[^"]+\.iso"' | tr -d '"' | head -n1)"
```

…or `wget` (keeps the filename by default):

```sh
wget "$(curl -fsSL https://api.github.com/repos/Paul1404/vmdp-mirror/releases/latest | grep -oE 'https://[^"]+\.iso"' | tr -d '"' | head -n1)"
```

**Windows (PowerShell)** — `Invoke-RestMethod` parses the JSON natively, so no
text-munging is needed:

```powershell
$a = (Invoke-RestMethod https://api.github.com/repos/Paul1404/vmdp-mirror/releases/latest).assets | Where-Object name -like *.iso
$ProgressPreference = 'SilentlyContinue'   # makes the download much faster
Invoke-WebRequest $a.browser_download_url -OutFile $a.name
```

**Pinned to a specific version** (browse [Releases](https://github.com/Paul1404/vmdp-mirror/releases) for tags):

```sh
wget https://github.com/Paul1404/vmdp-mirror/releases/download/v2.5.5.7.1/VMDP-WIN-2.5.5.iso
```

### Verify the download

Each release ships a `*.iso.sha256` alongside the ISO:

On Linux / macOS:

```sh
api=https://api.github.com/repos/Paul1404/vmdp-mirror/releases/latest
curl -fLO "$(curl -fsSL "$api" | grep -oE 'https://[^"]+\.iso"'        | tr -d '"' | head -n1)"
curl -fLO "$(curl -fsSL "$api" | grep -oE 'https://[^"]+\.iso\.sha256"' | tr -d '"' | head -n1)"
sha256sum -c VMDP-WIN-*.iso.sha256
```

On Windows (PowerShell), compare the hashes directly:

```powershell
$assets = (Invoke-RestMethod https://api.github.com/repos/Paul1404/vmdp-mirror/releases/latest).assets
$ProgressPreference = 'SilentlyContinue'
$assets | ForEach-Object { Invoke-WebRequest $_.browser_download_url -OutFile $_.name }
$want = (Get-Content (Get-ChildItem *.iso.sha256)).Split(' ')[0]
$got  = (Get-FileHash (Get-ChildItem *.iso) -Algorithm SHA256).Hash
if ($got -ieq $want) { "OK: $got" } else { "MISMATCH`n want $want`n got  $got" }
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

### Self-maintaining

This repo is designed to need zero attention:

- **No-op when unchanged** — the daily poll exits in seconds if the current
  version is already mirrored.
- **Stays scheduled** — a keepalive step makes an empty commit before GitHub's
  60-day inactivity cutoff would auto-disable the cron.
- **Keeps actions current** — [Dependabot](.github/dependabot.yml) bumps the
  GitHub Actions it uses, and [auto-merge](.github/workflows/dependabot-automerge.yml)
  merges those PRs without intervention.
- **Speaks up only when needed** — if the mirror genuinely can't run (e.g. SUSE
  changes the registry or label format), it opens a single tracking issue rather
  than failing silently.

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
