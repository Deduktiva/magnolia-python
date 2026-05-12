# shellcheck shell=bash
# Shared logic for the per-dep update-<dep>.sh pin-bump scripts.
# Sourced by per-dep wrappers; each wrapper passes its dep-specific
# config as flags. See update-openssl.sh and update-libmpdec.sh for
# the canonical wrapper shape.
#
# The wrappers exist as separate files (rather than a single
# update-pin.sh <dep> <version> entry point) because shell tab
# completion + grep-by-name is the dominant discovery UX, and because
# bash 3.2 doesn't have associative arrays for a clean per-dep
# config table inside one script.
#
# Compatible with bash 3.2 (the default on macOS).

# update_pin: bump a dependency's version + SHA-256 pin files.
#
# Flags (all required):
#   --name <dep>                e.g. "openssl"; pin files are
#                                MagPython/<dep>-version /
#                                MagPython/<dep>-sha256.
#   --version-pattern <glob>    bash case-glob the new version must
#                                match, e.g. '3.[0-9]*.[0-9]*'.
#                                Cross-major bumps that fail the glob
#                                are refused — the build glue may need
#                                a manual review across major lines.
#   --version-pattern-help <s>  human-readable description of the
#                                accepted version line, e.g.
#                                "3.x line", surfaced in error text.
#   --tarball-url <tmpl>        URL template for the tarball; literal
#                                "<v>" is replaced with the version.
#
# Positional: <version>         the only positional arg.
update_pin() {
    local name=
    local version_pattern=
    local version_pattern_help=
    local tarball_url_tmpl=
    local version=

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --name)                  name="$2"; shift 2 ;;
            --version-pattern)       version_pattern="$2"; shift 2 ;;
            --version-pattern-help)  version_pattern_help="$2"; shift 2 ;;
            --tarball-url)           tarball_url_tmpl="$2"; shift 2 ;;
            -*)
                echo "update_pin: unknown flag '$1'" >&2; return 64 ;;
            *)
                if [ -z "$version" ]; then
                    version="$1"; shift
                else
                    echo "update_pin: unexpected extra arg '$1'" >&2; return 64
                fi
                ;;
        esac
    done

    [ -n "$name" ]                  || { echo "update_pin: missing --name" >&2; return 64; }
    [ -n "$version_pattern" ]       || { echo "update_pin: missing --version-pattern" >&2; return 64; }
    [ -n "$version_pattern_help" ]  || { echo "update_pin: missing --version-pattern-help" >&2; return 64; }
    [ -n "$tarball_url_tmpl" ]      || { echo "update_pin: missing --tarball-url" >&2; return 64; }

    if [ -z "$version" ]; then
        # The wrapper's $0 is the user-visible script name; use it in
        # the usage string so the message reads naturally.
        echo "Usage: ${0##*/} <version>" >&2
        echo "  e.g.  ${0##*/} X.Y.Z (on the $version_pattern_help)" >&2
        return 64
    fi

    case "$version" in
        $version_pattern) ;;
        *)
            echo "Refusing to update: '$version' is not on the $version_pattern_help." >&2
            echo "A cross-major bump warrants a manual review of the build glue." >&2
            return 65
            ;;
    esac

    # Pin files live in the wrapper's directory (MagPython/), not this
    # helper's — both files are siblings, so it's the same path either
    # way, but wire it through BASH_SOURCE[1] explicitly to make the
    # intent clear.
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"

    local sha tarball_url
    tarball_url="$(_update_pin_substitute "$tarball_url_tmpl" "$version")"
    sha="$(_update_pin_download_and_hash "$tarball_url")" || return $?

    # Validate: 64 lowercase hex chars exactly. A truncated download or
    # an HTML error page returned with a 200 (some upstreams) would
    # otherwise quietly write a junk pin and fail the build only at the
    # next CI run with a confusing "SHA-256 mismatch" error.
    if [ "${#sha}" -ne 64 ]; then
        echo "Unexpected hash length ${#sha} (expected 64): '$sha'" >&2
        return 71
    fi
    case "$sha" in
        *[!0-9a-f]*)
            echo "Hash contains non-hex characters: $sha" >&2
            return 72
            ;;
    esac

    printf '%s\n' "$version" > "$script_dir/$name-version"
    printf '%s\n' "$sha"     > "$script_dir/$name-sha256"

    echo ""
    echo "Updated:"
    echo "  MagPython/$name-version -> $version"
    echo "  MagPython/$name-sha256  -> $sha"
    echo ""
    echo "Next steps:"
    echo "  1. Run a full Windows + Linux + macOS build to confirm the new"
    echo "     version compiles. The build cross-checks the downloaded"
    echo "     tarball against this SHA."
    echo "  2. Commit both pin files together:"
    echo "       git add MagPython/$name-version MagPython/$name-sha256"
    echo "       git commit -m 'Bump $name pin to $version'"
}

# Internal helpers — leading underscore signals "do not call directly
# from wrappers". Plain sed for substitution rather than parameter
# expansion so a literal "<v>" anywhere in the URL works (no
# bash-version-specific quirks around ${var//pat/repl}).

_update_pin_substitute() {
    # Replace literal "<v>" in $1 with $2.
    printf '%s\n' "$1" | sed "s|<v>|$2|g"
}

_update_pin_sha256_cmd() {
    if command -v shasum >/dev/null 2>&1; then echo "shasum -a 256"
    elif command -v sha256sum >/dev/null 2>&1; then echo "sha256sum"
    else echo "Need shasum or sha256sum on PATH" >&2; return 1
    fi
}

_update_pin_download_and_hash() {
    local url="$1"
    echo "Downloading $url ..." >&2
    local tmp
    tmp="$(mktemp 2>/dev/null || mktemp -t pin-tarball)"
    if ! curl --fail --silent --show-error --location --output "$tmp" "$url"; then
        echo "Failed to download tarball." >&2
        rm -f "$tmp"
        return 70
    fi
    local sha256_cmd
    sha256_cmd="$(_update_pin_sha256_cmd)" || { rm -f "$tmp"; return 1; }
    local sha
    sha="$($sha256_cmd "$tmp" | awk '{print tolower($1); exit}')"
    rm -f "$tmp"
    printf '%s' "$sha"
}
