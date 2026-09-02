#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
script="$root/.github/scripts/verify-release-assets.sh"
work=$(mktemp -d "${TMPDIR:-/tmp}/coderouter-release-assets.XXXXXX")
trap 'rm -rf "$work"' EXIT

fixture="$work/fixture"
mkdir -p "$fixture/package" "$work/bin" "$work/dist"
version=0.3.1

cat >"$fixture/manifest.json" <<EOF
{
  "version": "$version",
  "source_tag": "coderouter-v$version",
  "source_commit": "0123456789012345678901234567890123456789",
  "binaries": {
    "coderouter-darwin-arm64": "$(printf '%064d' 1)",
    "coderouter-darwin-x64": "$(printf '%064d' 2)",
    "coderouter-linux-arm64": "$(printf '%064d' 3)",
    "coderouter-linux-x64": "$(printf '%064d' 4)",
    "coderouter-win32-x64.exe": "$(printf '%064d' 5)"
  }
}
EOF
cat >"$fixture/package/package.json" <<EOF
{"name":"coderouter","version":"$version","bin":{"coderouter":"bin/coderouter.js","cr":"bin/coderouter.js"}}
EOF
printf '#!/usr/bin/env node\n' >"$fixture/package/bin-placeholder"
(cd "$fixture" && tar -czf coderouter-npm-launcher.tgz package)

wheel_names=(
  "coderouter-$version-py3-none-macosx_10_12_x86_64.whl"
  "coderouter-$version-py3-none-macosx_11_0_arm64.whl"
  "coderouter-$version-py3-none-manylinux_2_17_aarch64.manylinux2014_aarch64.whl"
  "coderouter-$version-py3-none-manylinux_2_17_x86_64.manylinux2014_x86_64.whl"
  "coderouter-$version-py3-none-win_amd64.whl"
)
for wheel in "${wheel_names[@]}"; do
  wheel_root="$work/wheel-${wheel%.whl}"
  mkdir -p "$wheel_root/coderouter-${version}.dist-info"
  printf 'Metadata-Version: 2.1\nName: coderouter\nVersion: %s\n' "$version" \
    >"$wheel_root/coderouter-${version}.dist-info/METADATA"
  (cd "$wheel_root" && zip -q -r "$fixture/$wheel" .)
done

sum_file="$fixture/SHA256SUMS"
: >"$sum_file"
for asset in manifest.json coderouter-npm-launcher.tgz "${wheel_names[@]}"; do
  sha256sum "$fixture/$asset" | sed "s#  $fixture/#  #" >>"$sum_file"
done

cat >"$work/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
fixture=${CODEROUTER_FIXTURE:?}
if [[ "$1" == api ]]; then
  endpoint=${@: -1}
  case "$endpoint" in
    repos/manaflow-ai/coderouter-releases/releases/tags/*)
      printf '{"tag_name":"v0.3.1","draft":false,"prerelease":false,"assets":[{"name":"SHA256SUMS"},{"name":"manifest.json"},{"name":"coderouter-npm-launcher.tgz"},{"name":"coderouter-0.3.1-py3-none-manylinux_2_17_x86_64.manylinux2014_x86_64.whl"}]}'
      ;;
    repos/manaflow-ai/coderouter-releases/git/ref/tags/*)
      printf '{"ref":"refs/tags/v0.3.1","object":{"type":"commit","sha":"0123456789012345678901234567890123456789"}}'
      ;;
    repos/manaflow-ai/coderouter-releases/compare/*)
      printf '{"status":"%s"}' "${CODEROUTER_COMPARE_STATUS:-behind}"
      ;;
    *)
      printf 'unexpected gh api endpoint: %s\n' "$endpoint" >&2
      exit 1
      ;;
  esac
  exit 0
fi
if [[ "$1" == release && "$2" == download ]]; then
  shift 2
  tag=$1
  shift
  output='.'
  patterns=()
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --repo) shift 2 ;;
      --dir) output=$2; shift 2 ;;
      --pattern) patterns+=("$2"); shift 2 ;;
      *) printf 'unexpected download argument: %s\n' "$1" >&2; exit 1 ;;
    esac
  done
  [[ "$tag" == v0.3.1 ]]
  for pattern in "${patterns[@]}"; do
    cp "$fixture/$pattern" "$output/$pattern"
  done
  exit 0
fi
printf 'unexpected gh command\n' >&2
exit 1
EOF
chmod 0755 "$work/bin/gh"

run_verify() {
  local kind=$1
  local out="$work/dist-$kind"
  mkdir "$out"
  CODEROUTER_FIXTURE="$fixture" \
  CODEROUTER_COMPARE_STATUS=behind \
  GITHUB_REPOSITORY=manaflow-ai/coderouter-releases \
  GH_TOKEN=test-token \
  PATH="$work/bin:$PATH" \
    "$script" "$kind" "$version" "$out"
}

run_verify npm
run_verify pypi

if GITHUB_REPOSITORY=manaflow-ai/coderouter-releases GH_TOKEN=test-token \
  PATH="$work/bin:$PATH" "$script" npm 01.2.3 "$work/bad-version"; then
  printf 'leading-zero version was accepted\n' >&2
  exit 1
fi

mkdir "$work/divergent"
if CODEROUTER_FIXTURE="$fixture" \
  CODEROUTER_COMPARE_STATUS=ahead \
  GITHUB_REPOSITORY=manaflow-ai/coderouter-releases \
  GH_TOKEN=test-token \
  PATH="$work/bin:$PATH" "$script" npm "$version" "$work/divergent"; then
  printf 'release tag outside main history was accepted\n' >&2
  exit 1
fi

printf 'release asset verification fixtures passed\n'
