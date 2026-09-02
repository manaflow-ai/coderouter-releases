#!/usr/bin/env bash
# Download and verify the exact release assets used by a registry publisher.
#
# This script deliberately accepts only a stable release from this repository.
# The caller must run it from a trusted workflow checkout and provide a
# read-only GitHub token through GH_TOKEN.
set -euo pipefail

usage() {
  printf 'usage: %s npm|pypi VERSION OUTPUT_DIR\n' "$0" >&2
}

if [[ "$#" -ne 3 ]]; then
  usage
  exit 2
fi

kind=$1
version=$2
output_dir=$3
repository=${GITHUB_REPOSITORY:-manaflow-ai/coderouter-releases}

case "$kind" in
  npm|pypi) ;;
  *)
    printf 'unsupported publisher: %s\n' "$kind" >&2
    exit 2
    ;;
esac

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
[[ -d "$output_dir" ]] || {
  printf 'output directory does not exist: %s\n' "$output_dir" >&2
  exit 1
}
[[ -z "$(find "$output_dir" -mindepth 1 -maxdepth 1 -print -quit)" ]] || {
  printf 'output directory must be empty: %s\n' "$output_dir" >&2
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
  printf 'release is missing, mutable, draft, prerelease, or has duplicate assets: %s\n' "$tag" >&2
  exit 1
}

# A release may use a lightweight or annotated tag. Resolve one annotated tag
# layer and require the resulting commit to be in this repository.
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

# Publishing a tag that is not an ancestor of protected main would allow a
# separately prepared artifact to bypass review of the release source.
# Compare from protected main to the candidate tag. A tag that is behind main
# is an ancestor; a tag that diverges or advances beyond main is rejected.
comparison_json=$(gh api "repos/$repository/compare/main...$tag")
jq -e '.status == "behind" or .status == "identical"' <<<"$comparison_json" >/dev/null || {
  printf 'release tag is not an ancestor of main: %s (%s)\n' "$tag" "$tag_sha" >&2
  exit 1
}

download_assets=(
  SHA256SUMS
  manifest.json
)
checksum_targets=(manifest.json)
pypi_wheels=()
case "$kind" in
  npm)
    download_assets+=(coderouter-npm-launcher.tgz)
    checksum_targets+=(coderouter-npm-launcher.tgz)
    ;;
  pypi)
    pypi_wheels=(
      "coderouter-$version-py3-none-macosx_10_12_x86_64.whl"
      "coderouter-$version-py3-none-macosx_11_0_arm64.whl"
      "coderouter-$version-py3-none-manylinux_2_17_aarch64.manylinux2014_aarch64.whl"
      "coderouter-$version-py3-none-manylinux_2_17_x86_64.manylinux2014_x86_64.whl"
      "coderouter-$version-py3-none-win_amd64.whl"
    )
    download_assets+=("${pypi_wheels[@]}")
    checksum_targets+=("${pypi_wheels[@]}")
    ;;
esac

download_args=(--repo "$repository" --dir "$output_dir" --pattern SHA256SUMS --pattern manifest.json)
for asset in "${download_assets[@]}"; do
  [[ "$asset" == SHA256SUMS || "$asset" == manifest.json ]] || download_args+=(--pattern "$asset")
done
gh release download "$tag" "${download_args[@]}"

for asset in "${download_assets[@]}"; do
  [[ -f "$output_dir/$asset" && ! -L "$output_dir/$asset" ]] || {
    printf 'missing or non-regular release asset: %s\n' "$asset" >&2
    exit 1
  }
done

# Require well-formed, unique checksum entries. Releases include checksums for
# binaries that are not published to either registry, so extra names are valid.
awk '
  NF != 2 || length($1) != 64 || $1 !~ /^[0-9a-fA-F]+$/ || index($2, "/") > 0 || $2 ~ /^-/ { exit 1 }
  ++seen[$2] != 1 { exit 1 }
' "$output_dir/SHA256SUMS" || {
  printf 'malformed SHA256SUMS in release %s\n' "$tag" >&2
  exit 1
}
for asset in "${checksum_targets[@]}"; do
  digest=$(awk -v asset="$asset" '
    $2 == asset { value = $1; count++ }
    END { if (count != 1) exit 1; print value }
  ' "$output_dir/SHA256SUMS") || {
    printf 'SHA256SUMS has no unique entry for %s\n' "$asset" >&2
    exit 1
  }
  actual_digest=$(sha256sum "$output_dir/$asset" | cut -d' ' -f1)
  [[ "$actual_digest" == "$digest" ]] || {
    printf 'checksum mismatch for %s\n' "$asset" >&2
    exit 1
  }
done

jq -e --arg version "$version" '
  .version == $version and
  .source_tag == ("coderouter-v" + $version) and
  (.source_commit | type == "string" and test("^[0-9a-f]{40}$")) and
  (.binaries | type == "object") and
  ((.binaries | keys) == [
    "coderouter-darwin-arm64",
    "coderouter-darwin-x64",
    "coderouter-linux-arm64",
    "coderouter-linux-x64",
    "coderouter-win32-x64.exe"
  ]) and
  (.binaries | to_entries | all(.value | test("^[0-9a-f]{64}$")))
' "$output_dir/manifest.json" >/dev/null || {
  printf 'release manifest does not bind the exact coderouter source and binaries\n' >&2
  exit 1
}

case "$kind" in
  npm)
    tar -xOf "$output_dir/coderouter-npm-launcher.tgz" package/package.json \
      | jq -e --arg version "$version" '
          .name == "coderouter" and
          .version == $version and
          .bin.coderouter == "bin/coderouter.js" and
          .bin.cr == "bin/coderouter.js"
        ' >/dev/null || {
      printf 'npm release package metadata does not match %s\n' "$version" >&2
      exit 1
    }
    ;;
  pypi)
    for wheel in "${pypi_wheels[@]}"; do
      mapfile -t metadata_paths < <(
        unzip -Z1 "$output_dir/$wheel" | grep -E '^[^/]+\.dist-info/METADATA$' || true
      )
      [[ "${#metadata_paths[@]}" -eq 1 ]] || {
        printf 'wheel has an invalid METADATA layout: %s\n' "$wheel" >&2
        exit 1
      }
      unzip -p "$output_dir/$wheel" "${metadata_paths[0]}" \
        | awk -v version="$version" '
            /^Name: / { name = $0 }
            /^Version: / { release = $0 }
            END { exit !(name == "Name: coderouter" && release == "Version: " version) }
          ' || {
        printf 'wheel metadata does not match %s: %s\n' "$version" "$wheel" >&2
        exit 1
      }
    done
    ;;
esac

printf 'verified %s release assets for %s\n' "$kind" "$tag"
