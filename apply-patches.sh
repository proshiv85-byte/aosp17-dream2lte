#!/bin/bash
#
# Apply the dream2lte patches to the AOSP projects they touch. Each project
# gets a local branch "dream2lte" (build/blueprint: "dream2lte-host"),
# recreated from the manifest revision, so running it again is safe.
#
#   ./apply-patches.sh /path/to/aosp
#
# NOTE: "repo sync" moves these projects back to the manifest revision.
# Re-run this script after every sync.

set -euo pipefail
HERE=$(dirname "$(readlink -f "$0")")
TOP=$(readlink -f "${1:?usage: $0 <aosp top dir>}")

cd "$HERE/patches"
for dir in $(find . -name "*.patch" -printf "%h\n" | sort -u); do
    p=${dir#./}
    br=dream2lte; [ "$p" = build/blueprint ] && br=dream2lte-host
    echo "== $p"
    base=$(git -C "$TOP/$p" for-each-ref --format='%(refname)' refs/remotes/m/ | head -1)
    git -C "$TOP/$p" checkout -q -B "$br" "$base^{commit}"
    git -C "$TOP/$p" am -q --3way "$HERE/patches/$p"/*.patch
done
echo "All patches applied."
