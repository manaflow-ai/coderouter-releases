#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
script="$root/.github/scripts/verify-package-identity.sh"
work=$(mktemp -d "${TMPDIR:-/tmp}/coderouter-identity-test.XXXXXX")
trap 'rm -rf "$work"' EXIT

version=0.3.1
wheel="coderouter-$version-py3-none-manylinux_2_17_x86_64.manylinux2014_x86_64.whl"
digest=$(printf '%064d' 0)

cat >"$work/npm.json" <<EOF
{"name":"coderouter","version":"$version","dist":{"tarball":"https://registry.npmjs.org/coderouter/-/coderouter-$version.tgz"}}
EOF
cat >"$work/pypi.json" <<EOF
{"info":{"name":"coderouter","version":"$version"},"urls":[{"packagetype":"bdist_wheel","filename":"$wheel","url":"https://files.pythonhosted.org/packages/example/$wheel","digests":{"sha256":"$digest"}}]}
EOF
cat >"$work/package.json" <<EOF
{"name":"coderouter","version":"$version","bin":{"coderouter":"bin/coderouter.js","cr":"bin/coderouter.js"}}
EOF

"$script" "$version" "$work/npm.json" "$work/pypi.json" "$work/package.json" "$digest"

if sed "s/\"version\":\"$version\"/\"version\":\"0.0.0\"/" "$work/pypi.json" >"$work/pypi-mismatch.json" \
  && "$script" "$version" "$work/npm.json" "$work/pypi-mismatch.json" "$work/package.json" "$digest"; then
  printf 'mismatched package metadata was accepted\n' >&2
  exit 1
fi

# Keep the registry smoke test bound to the selected release. A fake uvx makes
# both the argument contract and the version assertion deterministic offline.
mkdir "$work/bin"
cat >"$work/bin/uvx" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\0' "$@" >"$UVX_ARGS_FILE"
printf 'coderouter %s\n' "$UVX_OUTPUT_VERSION"
EOF
chmod 0755 "$work/bin/uvx"
expected_args=(
  --refresh
  --index-url https://pypi.org/simple
  --from "coderouter==$version"
  coderouter
  --version
)
PATH="$work/bin:$PATH" \
  UVX_ARGS_FILE="$work/uvx.args" \
  UVX_OUTPUT_VERSION="$version" \
  uvx --refresh --index-url https://pypi.org/simple \
    --from "coderouter==$version" coderouter --version \
    | grep -Fx "coderouter $version"
mapfile -d '' -t actual_args <"$work/uvx.args"
[[ "${actual_args[*]}" == "${expected_args[*]}" ]]

if PATH="$work/bin:$PATH" \
  UVX_ARGS_FILE="$work/uvx.args" \
  UVX_OUTPUT_VERSION=0.0.0 \
  uvx --refresh --index-url https://pypi.org/simple \
    --from "coderouter==$version" coderouter --version \
    | grep -Fx "coderouter $version"; then
  printf 'mismatched uvx output was accepted\n' >&2
  exit 1
fi

printf 'package identity fixtures passed\n'
