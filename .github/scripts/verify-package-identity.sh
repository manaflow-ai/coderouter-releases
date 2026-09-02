#!/usr/bin/env bash
# Validate that public registry metadata names the exact release artifact.
set -euo pipefail

if [[ "$#" -ne 5 ]]; then
  printf 'usage: %s VERSION NPM_JSON PYPI_JSON NPM_PACKAGE_JSON WHEEL_SHA256\n' "$0" >&2
  exit 2
fi
version=$1
npm_json=$2
pypi_json=$3
npm_package_json=$4
wheel_sha256=$5
expected_wheel="coderouter-$version-py3-none-manylinux_2_17_x86_64.manylinux2014_x86_64.whl"

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  printf 'invalid release version: %s\n' "$version" >&2
  exit 1
}
[[ "$wheel_sha256" =~ ^[[:xdigit:]]{64}$ ]] || {
  printf 'invalid wheel digest\n' >&2
  exit 1
}
jq -e --arg version "$version" '
  .name == "coderouter" and
  .version == $version and
  (.dist.tarball // "") == ("https://registry.npmjs.org/coderouter/-/coderouter-" + $version + ".tgz")
' "$npm_json" >/dev/null

jq -e --arg version "$version" --arg wheel "$expected_wheel" --arg digest "$wheel_sha256" '
  .info.name == "coderouter" and
  .info.version == $version and
  ([.urls[] | select(.packagetype == "bdist_wheel" and .filename == $wheel)] | length) == 1 and
  ([.urls[] | select(.packagetype == "bdist_wheel" and .filename == $wheel)][0]) as $artifact |
  ($artifact.digests.sha256 // "") == $digest and
  (($artifact.url // "") | test("^https://files\\.pythonhosted\\.org/[A-Za-z0-9._~:/-]+$")) and
  (($artifact.url // "") | endswith($wheel))
' "$pypi_json" >/dev/null

jq -e --arg version "$version" '
  .name == "coderouter" and
  .version == $version and
  .bin.coderouter == "bin/coderouter.js" and
  .bin.cr == "bin/coderouter.js"
' "$npm_package_json" >/dev/null
