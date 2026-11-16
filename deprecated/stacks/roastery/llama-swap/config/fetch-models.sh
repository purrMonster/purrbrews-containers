#!/usr/bin/env bash
# fetch-models.sh: download the files in models.lock into /models (the
# llm-models volume), each from its pinned revision and checked against its
# SHA-256 before it takes its final name. Runs inside the llama-swap image,
# which has bash, curl and sha256sum:
#   .\compose.ps1 llama-swap run --rm fetch-models
#
# Safe to re-run: a file already there with the right hash is skipped, a
# partial download resumes, a file with the wrong hash is replaced. Files that
# are no longer in models.lock are listed, never deleted.
set -euo pipefail

LOCK=${1:-/config/models.lock}
DEST=${MODELS_DIR:-/models}
mkdir -p "$DEST"

failed=0
wanted=()
while read -r file repo revision sha256 rest; do
    [[ -z "${file:-}" || "$file" == \#* ]] && continue
    if [[ -z "${sha256:-}" || -n "${rest:-}" || ! "$sha256" =~ ^[0-9a-f]{64}$ || "$file" == */* ]]; then
        echo "models.lock: bad line for '$file'" >&2; failed=1; continue
    fi
    wanted+=("$file")
    target="$DEST/$file"
    if [[ -f "$target" ]] && echo "$sha256  $target" | sha256sum --check --status; then
        echo "ok        $file"
        continue
    fi
    # A .part that finished downloading but was never renamed: a resume would
    # ask for bytes past its end, which the server refuses.
    if [[ -f "$target.part" ]] && echo "$sha256  $target.part" | sha256sum --check --status; then
        mv -f "$target.part" "$target"
        echo "ok        $file (finished earlier, verified)"
        continue
    fi
    url="https://huggingface.co/$repo/resolve/$revision/$file"
    echo "fetching  $file from $repo@${revision:0:12}"
    # --continue-at - resumes a .part left by an interrupted run.
    if ! curl --fail --location --progress-bar --retry 5 --retry-delay 5 --continue-at - \
            --output "$target.part" "$url"; then
        echo "FAILED    $file: download error (the .part is kept for a resume)" >&2
        failed=1; continue
    fi
    if echo "$sha256  $target.part" | sha256sum --check --status; then
        mv -f "$target.part" "$target"
        echo "ok        $file (verified)"
    else
        rm -f "$target.part"
        echo "FAILED    $file: SHA-256 mismatch, discarded" >&2
        failed=1
    fi
done < "$LOCK"

for present in "$DEST"/*.gguf; do
    [[ -e "$present" ]] || continue
    name=$(basename "$present")
    [[ " ${wanted[*]} " == *" $name "* ]] || echo "unused    $name (not in models.lock; remove by hand if unwanted)"
done

df -h "$DEST" | tail -1 | awk '{print "volume    " $4 " free of " $2}'
exit "$failed"
