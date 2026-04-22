#!/usr/bin/env bash
# install-cubrid-jdbc.sh
#
# Intended destination (in the BenchBase internal fork): scripts/install-cubrid-jdbc.sh
#
# Purpose: satisfy BenchBase's Maven CUBRID profile (ADR-2 of the consensus plan)
# by installing the CUBRID JDBC jar into the local Maven repository so that
# `mvn package -P cubrid` can resolve the `cubrid:cubrid-jdbc:<version>`
# coordinate without publishing to any remote repo.
#
# Idempotent: re-running after a successful install is a no-op (same coord +
# same jar → Maven overwrites but result is identical).
#
# Prerequisites:
#   - WS-0/M0 must have produced the CUBRID JDBC jar. Per plan M0 dual-branch:
#       1. Try standalone build: cd cubrid/cubrid-jdbc && ant dist
#       2. If that fails, fall back to the parent CUBRID CMake path which
#          invokes copy_submodule_jdbc.cmake (see
#          /data/cub_sys/cubrid/pl_engine/cmake/copy_submodule_jdbc.cmake).
#   - mvn on PATH (BenchBase itself requires Maven; this script does too).
#
# Usage:
#   ./scripts/install-cubrid-jdbc.sh [path-to-jar]
#   ./scripts/install-cubrid-jdbc.sh  # auto-detects from conventional locations

set -euo pipefail

# Auto-source the project-local CUBRID env so ${CUBRID}/jdbc/*.jar glob
# resolution below works in non-login shells.
if [[ -z "${CUBRID:-}" && -f /data/cub_sys/.cubrid.sh ]]; then
    # shellcheck disable=SC1091
    . /data/cub_sys/.cubrid.sh
fi

GROUP_ID="cubrid"
ARTIFACT_ID="cubrid-jdbc"

# Candidate jar locations, searched in order. The installed CUBRID ships a
# pre-built versioned jar under ${CUBRID}/jdbc/ (e.g.
# cubrid-jdbc-11.3.2.0058.jar); prefer it over building from submodule.
CANDIDATES=(
    "${1:-}"
    "${CUBRID_JDBC_JAR:-}"
    "${CUBRID:-/opt/cubrid}/jdbc/cubrid-jdbc-*.jar"
    "/data/cub_sys/cubrid/cubrid-jdbc/cubrid-jdbc-*.jar"
    "/data/cub_sys/cubrid/cubrid-jdbc/output/cubrid-jdbc-*.jar"
    "/data/cub_sys/cubrid/pl_engine/build/jdbc/cubrid-jdbc-*.jar"
    "${CUBRID:-/opt/cubrid}/jdbc/cubrid_jdbc.jar"
)

JAR=""
for cand in "${CANDIDATES[@]}"; do
    [[ -z "$cand" ]] && continue
    # Expand globs; take the first versioned match that exists and is readable.
    # Prefer versioned jars (cubrid-jdbc-X.Y.Z.jar) over the unversioned alias
    # (cubrid_jdbc.jar) so the Maven coordinate carries a real version.
    for f in $cand; do
        if [[ -f "$f" && -r "$f" && "$f" != *cubrid_jdbc.jar ]]; then
            JAR="$f"
            break 2
        fi
    done
done
# Fallback: accept the unversioned alias if nothing else matched.
if [[ -z "$JAR" ]]; then
    for cand in "${CANDIDATES[@]}"; do
        [[ -z "$cand" ]] && continue
        for f in $cand; do
            if [[ -f "$f" && -r "$f" ]]; then
                JAR="$f"
                break 2
            fi
        done
    done
fi

if [[ -z "$JAR" ]]; then
    echo "ERROR: CUBRID JDBC jar not found. Checked:" >&2
    for cand in "${CANDIDATES[@]}"; do
        [[ -n "$cand" ]] && echo "  - $cand" >&2
    done
    echo "" >&2
    echo "Build the jar first (see plan M0 dual-branch):" >&2
    echo "  1. Standalone: cd /data/cub_sys/cubrid/cubrid-jdbc && ant dist" >&2
    echo "  2. Fallback: build CUBRID with CMake (parent tree will copy jar)" >&2
    echo "" >&2
    echo "Or pass the jar path explicitly:" >&2
    echo "  $0 /path/to/cubrid-jdbc-<version>.jar" >&2
    exit 2
fi

# Derive version from filename. Expected patterns:
#   JDBC-11.4.0.1234-cubrid.jar
#   cubrid-jdbc-11.4.0.1234.jar
#   cubrid_jdbc.jar (fallback: query MANIFEST.MF)
VERSION=""
FN="$(basename "$JAR")"
if [[ "$FN" =~ ^JDBC-([0-9.]+)-cubrid\.jar$ ]]; then
    VERSION="${BASH_REMATCH[1]}"
elif [[ "$FN" =~ ^cubrid-jdbc-([0-9.]+)\.jar$ ]]; then
    VERSION="${BASH_REMATCH[1]}"
else
    VERSION="$(unzip -p "$JAR" META-INF/MANIFEST.MF 2>/dev/null \
               | awk -F': ' '/^Implementation-Version|^Bundle-Version/ {print $2; exit}' \
               | tr -d '\r')"
fi

if [[ -z "$VERSION" ]]; then
    echo "ERROR: could not derive version from $JAR" >&2
    echo "Pass CUBRID_JDBC_VERSION=<version> in the environment to override." >&2
    exit 3
fi

: "${CUBRID_JDBC_VERSION:=$VERSION}"

if ! command -v mvn >/dev/null 2>&1; then
    echo "ERROR: mvn not on PATH. BenchBase requires Maven; install it first." >&2
    exit 4
fi

echo "Installing $JAR as ${GROUP_ID}:${ARTIFACT_ID}:${CUBRID_JDBC_VERSION} ..."
mvn install:install-file \
    -Dfile="$JAR" \
    -DgroupId="$GROUP_ID" \
    -DartifactId="$ARTIFACT_ID" \
    -Dversion="$CUBRID_JDBC_VERSION" \
    -Dpackaging=jar \
    -DgeneratePom=true \
    -q

echo "OK: ${GROUP_ID}:${ARTIFACT_ID}:${CUBRID_JDBC_VERSION} installed."
echo "The BenchBase cubrid Maven profile should reference:"
echo "  <dependency>"
echo "    <groupId>${GROUP_ID}</groupId>"
echo "    <artifactId>${ARTIFACT_ID}</artifactId>"
echo "    <version>${CUBRID_JDBC_VERSION}</version>"
echo "    <scope>runtime</scope>"
echo "  </dependency>"
