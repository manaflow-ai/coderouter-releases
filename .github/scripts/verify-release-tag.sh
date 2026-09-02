#!/usr/bin/env bash
# Verify that a stable release tag is published, immutable in shape, and an
# ancestor of protected main before any release asset is consumed.
set -euo pipefail

if [[ "$#" -ne 1 ]]; then
  printf 'usage: %s VERSION\n' "$0" >&2
  exit 2
fi

version=$1
repository=${GITHUB_REPOSITORY:-manaflow-ai/coderouter-releases}
[[ "$repository" == manaflow-ai/coderouter-releases ]] || {
  printf 'unexpected repository: %s\n' "$repository" >&2
  exit 1
}
[[ "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || {
  printf 'invalid stable release version: %s\n' "$version" >&2
  exit 1
}
[[ -n "${GH_TOKEN:-}" ]] || {
  printf 'GH_TOKEN is required\n' >&2
  exit 1
}

tag="v$version"
release_json=$(gh api "repos/$repository/releases/tags/$tag")
jq -e --arg tag "$tag" '
  .tag_name == $tag and
  .draft == false and
  .prerelease == false and
  ([.assets[].name] | length == (unique | length))
' <<<"$release_json" >/dev/null || {
  printf 'release is missing, draft, prerelease, or has duplicate assets: %s\n' "$tag" >&2
  exit 1
}

# A release may use a lightweight or annotated tag. Resolve one annotated tag
# layer and require the resulting object to be a commit.
tag_json=$(gh api "repos/$repository/git/ref/tags/$tag")
tag_type=$(jq -er '.object.type' <<<"$tag_json")
tag_sha=$(jq -er '.object.sha | select(test("^[0-9a-f]{40}$"))' <<<"$tag_json")
case "$tag_type" in
  commit) ;;
  tag)
    annotated_json=$(gh api "repos/$repository/git/tags/$tag_sha")
    jq -e '.object.type == "commit" and (.object.sha | test("^[0-9a-f]{40}$"))' <<<"$annotated_json" >/dev/null || {
      printf 'release tag does not resolve to a commit: %s\n' "$tag" >&2
      exit 1
    }
    tag_sha=$(jq -er '.object.sha' <<<"$annotated_json")
    ;;
  *)
    printf 'unsupported release tag object type: %s\n' "$tag_type" >&2
    exit 1
    ;;
esac

# Compare from protected main to the candidate tag. A tag that is behind main
# is an ancestor; a tag that diverges or advances beyond main is rejected.
comparison_json=$(gh api "repos/$repository/compare/main...$tag")
jq -e '.status == "behind" or .status == "identical"' <<<"$comparison_json" >/dev/null || {
  printf 'release tag is not an ancestor of main: %s (%s)\n' "$tag" "$tag_sha" >&2
  exit 1
}

printf 'verified release tag %s (%s)\n' "$tag" "$tag_sha"
