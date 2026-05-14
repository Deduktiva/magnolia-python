#!/usr/bin/env bash
# Generate the per-platform release-notes fragment that ships alongside
# the build artifact (MagPython-<platform>.md). Invoked by the
# "Generate build details" step in .github/workflows/Build All.yml; the
# Release workflow concatenates the fragments verbatim into body.md.
#
# Usage:
#   MagPython/build-details.sh <platform> [output-path]
#
# Platforms: windows-x86 | windows-x64 | linux-x86_64 | macos-arm64
#
# Sources of truth (kept in sync with the build scripts so the .md never
# drifts from what was actually built):
#   MagPython/python-version       -> PY_VERSION       (downloaded at
#                                     build time, see build-common.sh /
#                                     download-python.ps1)
#   MagPython/openssl-version      -> OPENSSL_VERSION  (downloaded at
#                                     build time, see build-common.sh /
#                                     download-openssl.ps1)
#   MagPython/libmpdec-version     -> LIBMPDEC_VERSION (downloaded at
#                                     build time, see build-common.sh /
#                                     download-libmpdec.ps1)
#   MagPython/common.props         -> MSVC toolset       [windows-x86, windows-x64]
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

PY_VERSION="$(tr -d '[:space:]' < "$REPO/MagPython/python-version")"

OPENSSL_VERSION="$(tr -d '[:space:]' < "$REPO/MagPython/openssl-version")"

LIBMPDEC_VERSION="$(tr -d '[:space:]' < "$REPO/MagPython/libmpdec-version")"

# Qt6 + PySide6 ship in the Linux, macOS, and windows-x64 artifacts;
# windows-x86 has none (Qt 6 dropped 32-bit Windows entirely). The
# per-platform case statement below references them in those three arms
# only.
QT6_VERSION="$(tr -d '[:space:]' < "$REPO/MagPython/qt6-version")"
PYSIDE6_VERSION="$(tr -d '[:space:]' < "$REPO/MagPython/pyside6-version")"

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
    windows-x86|windows-x64)
        MSVC_TOOLSET="$(sed -n -E \
            's|.*<PlatformToolset[^>]*>([^<]+)</PlatformToolset>.*|\1|p' \
            "$REPO/MagPython/common.props" | head -1)"
        require MSVC_TOOLSET
        # Map platform suffix to its human-readable form for the heading.
        case "$PLATFORM" in
            windows-x86) ARCH_TITLE="x86" ;;
            windows-x64) ARCH_TITLE="x64" ;;
        esac
        # windows-x64 also bundles Qt6 + PySide6; windows-x86 doesn't
        # (Qt 6 has no 32-bit Windows port).
        QT_LINE=""
        PYSIDE6_LINE=""
        if [ "$PLATFORM" = "windows-x64" ]; then
            require QT6_VERSION
            require PYSIDE6_VERSION
            QT_LINE="- Qt ${QT6_VERSION} (qtbase Core)"
            PYSIDE6_LINE="- PySide6 ${PYSIDE6_VERSION} (Core module)"
        fi
        cat > "$OUT" <<EOF
### Windows ${ARCH_TITLE}
- Python ${PY_VERSION}
- OpenSSL ${OPENSSL_VERSION}
- mpdecimal ${LIBMPDEC_VERSION}
${QT_LINE:+$QT_LINE
}${PYSIDE6_LINE:+$PYSIDE6_LINE
}- MSVC Toolset ${MSVC_TOOLSET}
EOF
        ;;
    linux-x86_64)
        CONTAINER="${CONTAINER_IMAGE:-$(matrix_field container)}"
        MANYLINUX_TAG="$(printf '%s' "$CONTAINER" \
            | sed -n -E 's|.*quay\.io/pypa/(manylinux[^ ]+).*|\1|p')"
        require MANYLINUX_TAG
        require QT6_VERSION
        require PYSIDE6_VERSION
        cat > "$OUT" <<EOF
### Linux x86_64
- Python ${PY_VERSION}
- OpenSSL ${OPENSSL_VERSION}
- mpdecimal ${LIBMPDEC_VERSION}
- Qt ${QT6_VERSION} (qtbase Core)
- PySide6 ${PYSIDE6_VERSION} (Core module)
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
        require QT6_VERSION
        require PYSIDE6_VERSION
        cat > "$OUT" <<EOF
### macOS arm64
- Python ${PY_VERSION}
- OpenSSL ${OPENSSL_VERSION}
- mpdecimal ${LIBMPDEC_VERSION}
- Qt ${QT6_VERSION} (qtbase Core)
- PySide6 ${PYSIDE6_VERSION} (Core module)
- ${RUNNER} runner, MACOSX_DEPLOYMENT_TARGET=${MACOS_DEPLOY_TARGET}
EOF
        ;;
    *)
        echo "no build-details template for platform $PLATFORM" >&2
        exit 1
        ;;
esac

cat "$OUT"
