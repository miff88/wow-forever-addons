#!/usr/bin/env bash
# Release one addon's current .toc version, if it hasn't been released yet.
#   1. upload the zip to CurseForge (Forever 1.60.1) when the addon is in curseforge.json
#   2. create the GitHub release, which also creates the tag "<Addon>-v<version>"
# The GitHub release is made last, so a failed CurseForge upload is retried next run.
# Usage: release.sh <AddonFolder>     Needs: GH_TOKEN, CF_API_TOKEN (for CurseForge), jq, zip
set -euo pipefail

addon="$1"
toc="${addon}/${addon}.toc"
[ -f "$toc" ] || { echo "::error::$toc not found"; exit 1; }

version="$(grep -m1 '^## Version:' "$toc" | sed 's/^## Version:[[:space:]]*//' | tr -d '\r')"
tag="${addon}-v${version}"

if gh release view "$tag" >/dev/null 2>&1; then
    echo "$addon $version is already released ($tag), nothing to do."
    exit 0
fi

interface="$(grep -m1 '^## Interface:' "$toc" | sed 's/^## Interface:[[:space:]]*//' | tr -d '\r' | cut -d, -f1)"
# 16001 -> 1.60.1 (read from the right, like the BigWigs packager)
game_version="$((interface / 10000)).$(((interface / 100) % 100)).$((interface % 100))"
zip_name="${addon}-${version}.zip"
# the name players see: the toc Title without colour codes ("Battle Shout Notice")
title="$(grep -m1 '^## Title:' "$toc" | sed 's/^## Title:[[:space:]]*//' | tr -d '\r' | sed -E 's/\|c[0-9a-fA-F]{8}//g; s/\|r//g')"
[ -n "$title" ] || title="$addon"
echo "Releasing $addon $version (game version $game_version)"

rm -f "$zip_name"
zip -qr "$zip_name" "$addon"
python3 .github/scripts/changelog.py "$addon" "$version" CHANGELOG.md > notes.md
cat notes.md

project_id="$(jq -r --arg a "$addon" '.[$a] // empty' curseforge.json)"
if [ -n "$project_id" ]; then
    if [ -z "${CF_API_TOKEN:-}" ]; then
        echo "::error::The CF_API_TOKEN repository secret is not set, so $addon can't be uploaded to CurseForge."
        exit 1
    fi
    # CurseForge's id for this game version; Forever's version type is 88568
    curl -sSf -H "X-Api-Token: $CF_API_TOKEN" https://wow.curseforge.com/api/game/versions > versions.json
    version_id="$(jq -r --arg v "$game_version" '
        ([.[] | select(.name == $v and .gameVersionTypeID == 88568)] + [.[] | select(.name == $v)])
        | .[0].id // empty' versions.json)"
    [ -n "$version_id" ] || { echo "::error::CurseForge has no game version $game_version"; exit 1; }

    metadata="$(jq -n --rawfile log notes.md --argjson gv "$version_id" --arg name "$title $version" \
        '{changelog: $log, changelogType: "markdown", displayName: $name, gameVersions: [$gv], releaseType: "release"}')"
    curl -sS --fail-with-body \
        -H "X-Api-Token: $CF_API_TOKEN" \
        --form-string "metadata=$metadata" \
        -F "file=@${zip_name}" \
        "https://wow.curseforge.com/api/projects/${project_id}/upload-file"
    echo
    echo "Uploaded $addon $version to CurseForge project $project_id"
fi

gh release create "$tag" "$zip_name" --target "${GITHUB_SHA}" \
    --title "${addon} ${version}" --notes-file notes.md
echo "GitHub release $tag created"
