#!/usr/bin/env bash
#
# mirror.sh — mirror the latest SUSE VMDP ISO to a GitHub Release.
#
# The VMDP ISO is shipped as a scratch container image on registry.suse.com.
# The image's only content is a single ISO under /disk/. This script:
#
#   1. Resolves the upstream version from the image config labels
#      (cheap: ~8 KB, no need to pull the 24 MB layer just to check).
#   2. Skips everything if a release for that version already exists
#      (idempotent — same version is a no-op).
#   3. Otherwise pulls the layer, extracts the ISO, and publishes it
#      as a GitHub Release asset together with a SHA256 checksum.
#
# Dependencies: bash, curl, jq, tar, sha256sum (coreutils), gh.
# All are present on ubuntu-latest. Auth to the registry is anonymous;
# the only credential needed is GITHUB_TOKEN / gh auth for publishing.
#
# Usage:
#   ./scripts/mirror.sh            # detect + publish if new (needs gh auth)
#   ./scripts/mirror.sh --check    # print the upstream version and exit
#   ./scripts/mirror.sh --no-publish <dir>
#                                  # download + extract the ISO into <dir>,
#                                  # but do not touch GitHub
#
set -euo pipefail

# ----------------------------------------------------------------------------
# Configuration
# ----------------------------------------------------------------------------
REGISTRY="${VMDP_REGISTRY:-registry.suse.com}"
REPOSITORY="${VMDP_REPOSITORY:-suse/vmdp/vmdp}"
TAG="${VMDP_TAG:-latest}"
AUTH_REALM="https://scc.suse.com/api/registry/authorize"
AUTH_SERVICE="SUSE Linux Docker Registry"
GH_REPO="${GH_REPO:-Paul1404/vmdp-mirror}"

ACCEPT_MANIFEST=$(printf '%s,' \
  "application/vnd.docker.distribution.manifest.v2+json" \
  "application/vnd.oci.image.manifest.v1+json" \
  "application/vnd.docker.distribution.manifest.list.v2+json" \
  "application/vnd.oci.image.index.v1+json")
ACCEPT_MANIFEST="${ACCEPT_MANIFEST%,}"

log()  { printf '>>> %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# ----------------------------------------------------------------------------
# Registry helpers (anonymous bearer auth)
# ----------------------------------------------------------------------------
get_token() {
  curl -fsSL --get \
    --data-urlencode "service=${AUTH_SERVICE}" \
    --data-urlencode "scope=repository:${REPOSITORY}:pull" \
    "${AUTH_REALM}" | jq -r '.token'
}

# Resolve TAG to a concrete image manifest JSON, following a manifest
# list / OCI index to the linux/amd64 entry if necessary.
get_manifest() {
  local token="$1" manifest digest
  manifest=$(curl -fsSL \
    -H "Authorization: Bearer ${token}" \
    -H "Accept: ${ACCEPT_MANIFEST}" \
    "https://${REGISTRY}/v2/${REPOSITORY}/manifests/${TAG}")

  if echo "${manifest}" | jq -e '.manifests' >/dev/null 2>&1; then
    digest=$(echo "${manifest}" | jq -r '
      .manifests[]
      | select(.platform.architecture == "amd64" and .platform.os == "linux")
      | .digest' | head -n1)
    [ -n "${digest}" ] || die "no linux/amd64 manifest in index"
    manifest=$(curl -fsSL \
      -H "Authorization: Bearer ${token}" \
      -H "Accept: ${ACCEPT_MANIFEST}" \
      "https://${REGISTRY}/v2/${REPOSITORY}/manifests/${digest}")
  fi
  echo "${manifest}"
}

# ----------------------------------------------------------------------------
# Steps
# ----------------------------------------------------------------------------

# Echoes the upstream version (from image labels) to stdout.
detect_version() {
  local token manifest config_digest version
  token=$(get_token)
  manifest=$(get_manifest "${token}")
  config_digest=$(echo "${manifest}" | jq -r '.config.digest')
  [ -n "${config_digest}" ] && [ "${config_digest}" != "null" ] \
    || die "could not read config digest from manifest"

  version=$(curl -fsSL -L \
    -H "Authorization: Bearer ${token}" \
    "https://${REGISTRY}/v2/${REPOSITORY}/blobs/${config_digest}" \
    | jq -r '.config.Labels["org.opencontainers.image.version"] // empty')
  [ -n "${version}" ] || die "could not read version label from image config"
  echo "${version}"
}

# Downloads the single layer and extracts the ISO into the given directory.
# Echoes the absolute path of the extracted ISO to stdout.
download_iso() {
  local outdir="$1"
  local token manifest layer_digest workdir iso
  token=$(get_token)
  manifest=$(get_manifest "${token}")

  # A VMDP image has exactly one layer holding the ISO; if that ever
  # changes, take the largest layer.
  layer_digest=$(echo "${manifest}" | jq -r '
    [.layers[]] | max_by(.size) | .digest')
  [ -n "${layer_digest}" ] && [ "${layer_digest}" != "null" ] \
    || die "could not determine ISO layer digest"

  workdir=$(mktemp -d)
  # shellcheck disable=SC2064
  trap "rm -rf '${workdir}'" RETURN

  log "downloading layer ${layer_digest} ..."
  curl -fsSL -L \
    -H "Authorization: Bearer ${token}" \
    "https://${REGISTRY}/v2/${REPOSITORY}/blobs/${layer_digest}" \
    -o "${workdir}/layer.tar.gz"

  log "extracting ISO ..."
  mkdir -p "${workdir}/root"
  tar -xzf "${workdir}/layer.tar.gz" -C "${workdir}/root"

  iso=$(find "${workdir}/root" -type f -name '*.iso' | head -n1)
  [ -n "${iso}" ] || die "no .iso found in image layer"

  mkdir -p "${outdir}"
  mv "${iso}" "${outdir}/"
  echo "${outdir}/$(basename "${iso}")"
}

release_exists() {
  local version="$1"
  gh release view "v${version}" --repo "${GH_REPO}" >/dev/null 2>&1
}

publish_release() {
  local version="$1" iso="$2"
  local name sum
  name=$(basename "${iso}")
  ( cd "$(dirname "${iso}")" && sha256sum "${name}" > "${name}.sha256" )
  sum=$(cut -d' ' -f1 < "${iso}.sha256")

  local notes
  notes=$(cat <<EOF
Automated mirror of the SUSE Virtual Machine Driver Pack (VMDP) ISO.

| | |
|---|---|
| **Upstream version** | \`${version}\` |
| **ISO** | \`${name}\` |
| **SHA256** | \`${sum}\` |
| **Source image** | \`${REGISTRY}/${REPOSITORY}:${version}\` |

Pulled from the official SUSE container registry and re-published here for
faster downloads. See the [README](https://github.com/${GH_REPO}#readme) for
download instructions.

Upstream: <https://www.suse.com/download/suse-vmdp/>
EOF
)

  log "creating release v${version} ..."
  gh release create "v${version}" \
    --repo "${GH_REPO}" \
    --title "VMDP ${version}" \
    --notes "${notes}" \
    --latest \
    "${iso}" "${iso}.sha256"
}

emit_output() {
  # Surface key/value pairs to the GitHub Actions step output, if running there.
  [ -n "${GITHUB_OUTPUT:-}" ] || return 0
  printf '%s\n' "$@" >> "${GITHUB_OUTPUT}"
}

# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------
main() {
  case "${1:-}" in
    --check)
      detect_version
      ;;
    --no-publish)
      local dir="${2:-./out}"
      download_iso "${dir}"
      ;;
    "")
      local version iso
      version=$(detect_version)
      log "upstream version: ${version}"
      emit_output "version=${version}"

      if release_exists "${version}"; then
        log "release v${version} already exists — nothing to do."
        emit_output "published=false"
        exit 0
      fi

      local dir
      dir=$(mktemp -d)
      iso=$(download_iso "${dir}")
      log "extracted: $(basename "${iso}") ($(du -h "${iso}" | cut -f1))"
      publish_release "${version}" "${iso}"
      rm -rf "${dir}"
      log "done."
      emit_output "published=true"
      ;;
    *)
      die "unknown argument: $1 (use --check or --no-publish [dir])"
      ;;
  esac
}

main "$@"
