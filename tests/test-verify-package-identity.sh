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

printf 'package identity fixtures passed\n'
