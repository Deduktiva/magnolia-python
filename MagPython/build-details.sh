#!/usr/bin/env bash
# Generate the per-platform release-notes fragment that ships alongside
# the build artifact (MagPython-<platform>.md). Invoked by the
# "Generate build details" step in .github/workflows/Build All.yml; the
# Release workflow concatenates the fragments verbatim into body.md.
#
# Usage:
#   MagPython/build-details.sh <platform> [output-path]
#
# Platforms: windows-x86 | linux-x86_64 | macos-arm64
#
# Sources of truth (kept in sync with the build scripts so the .md never
# drifts from what was actually built):
#   Python/Include/patchlevel.h    -> PY_VERSION
#   openssl/VERSION.dat            -> OPENSSL_VERSION  (OpenSSL 3 generates
#                                     opensslv.h from a template at
#                                     ./Configure time, so VERSION.dat is
#                                     the only file present pre-build)
#   MagPython/libmpdec-version     -> LIBMPDEC_VERSION (downloaded at
#                                     build time, see build-common.sh /
#                                     download-libmpdec.ps1)
#   MagPython/common.props         -> MSVC toolset       [windows-x86]
#   MagPython/build-macos.sh       -> MACOSX_DEPLOYMENT_TARGET [macos-arm64]
#
# Matrix-supplied values (container image, runner label) are read from
# the env vars CONTAINER_IMAGE / RUNNER_LABEL when set (CI passes them
# from matrix.container / matrix.runs-on); otherwise they fall back to
# parsing the matrix entry out of Build All.yml so this script can be
# run locally with just a platform name.

set -euo pipefail

PLATFORM="${1:-}"
[ -n "$PLATFORM" ] || {
    echo "usage: $0 <platform> [output-path]" >&2
    exit 1
}

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${2:-MagPython-$PLATFORM.md}"

require() {
    [ -n "${!1:-}" ] || { echo "failed to detect $1" >&2; exit 1; }
}

PY_VERSION="$(awk '
    /^#define PY_VERSION[[:space:]]/ { gsub(/"/, "", $3); print $3; exit }
' "$REPO/Python/Include/patchlevel.h")"

OPENSSL_VERSION="$(awk -F= '
    /^MAJOR=/           { gsub(/[ \t\r]/, "", $2); maj=$2 }
    /^MINOR=/           { gsub(/[ \t\r]/, "", $2); min=$2 }
    /^PATCH=/           { gsub(/[ \t\r]/, "", $2); pat=$2 }
    /^PRE_RELEASE_TAG=/ { gsub(/[ \t\r]/, "", $2); pre=$2 }
    /^BUILD_METADATA=/  { gsub(/[ \t\r]/, "", $2); meta=$2 }
    END {
        v = maj"."min"."pat
        if (pre  != "") v = v"-"pre
        if (meta != "") v = v"+"meta
        print v
    }
' "$REPO/openssl/VERSION.dat")"

LIBMPDEC_VERSION="$(tr -d '[:space:]' < "$REPO/MagPython/libmpdec-version")"

require PY_VERSION
require OPENSSL_VERSION
require LIBMPDEC_VERSION

# Read a `<field>:` value out of the matrix entry whose `platform:` matches
# $PLATFORM. Used as the local-dev fallback when CI hasn't injected the
# matrix value via env. Stops at the next `- platform:` line so we don't
# leak fields from a sibling entry.
matrix_field() {
    local field="$1"
    awk -v plat="$PLATFORM" -v field="$field" '
        $0 ~ /^[[:space:]]*-[[:space:]]*platform:[[:space:]]*/ {
            cur = $0
            sub(/.*platform:[[:space:]]*/, "", cur)
            sub(/[[:space:]]*$/, "", cur)
            next
        }
        cur == plat && match($0, "^[[:space:]]*"field":[[:space:]]*") {
            v = substr($0, RSTART+RLENGTH)
            sub(/[[:space:]]*$/, "", v)
            print v
            exit
        }
    ' "$REPO/.github/workflows/Build All.yml"
}

case "$PLATFORM" in
    windows-x86)
        MSVC_TOOLSET="$(sed -n -E \
            's|.*<PlatformToolset[^>]*>([^<]+)</PlatformToolset>.*|\1|p' \
            "$REPO/MagPython/common.props" | head -1)"
        require MSVC_TOOLSET
        cat > "$OUT" <<EOF
### Windows x86
- Python ${PY_VERSION}
- OpenSSL ${OPENSSL_VERSION}
- mpdecimal ${LIBMPDEC_VERSION}
- MSVC Toolset ${MSVC_TOOLSET}
EOF
        ;;
    linux-x86_64)
        CONTAINER="${CONTAINER_IMAGE:-$(matrix_field container)}"
        MANYLINUX_TAG="$(printf '%s' "$CONTAINER" \
            | sed -n -E 's|.*quay\.io/pypa/(manylinux[^ ]+).*|\1|p')"
        require MANYLINUX_TAG
        cat > "$OUT" <<EOF
### Linux x86_64
- Python ${PY_VERSION}
- OpenSSL ${OPENSSL_VERSION}
- mpdecimal ${LIBMPDEC_VERSION}
- ${MANYLINUX_TAG}
EOF
        ;;
    macos-arm64)
        RUNNER="${RUNNER_LABEL:-$(matrix_field runs-on)}"
        require RUNNER
        MACOS_DEPLOY_TARGET="$(sed -n -E \
            's|^export MACOSX_DEPLOYMENT_TARGET=([0-9.]+).*|\1|p' \
            "$REPO/MagPython/build-macos.sh" | head -1)"
        require MACOS_DEPLOY_TARGET
        cat > "$OUT" <<EOF
### macOS arm64
- Python ${PY_VERSION}
- OpenSSL ${OPENSSL_VERSION}
- mpdecimal ${LIBMPDEC_VERSION}
- ${RUNNER} runner, MACOSX_DEPLOYMENT_TARGET=${MACOS_DEPLOY_TARGET}
EOF
        ;;
    *)
        echo "no build-details template for platform $PLATFORM" >&2
        exit 1
        ;;
esac

cat "$OUT"
