# coderouter releases

Public, checksum-verified binary distribution for
[coderouter](https://cmux.com/coderouter).

The product source remains private during beta. Every release records the
corresponding immutable source tag and commit from
`manaflow-ai/coderouter`. npm and PyPI publication use GitHub OIDC trusted
publishing; this repository stores no registry tokens.

Release publishing is limited to the protected `main` branch. The
`npm-coderouter` and `pypi-coderouter` environments require approval from
`@austinywang` or `@azooz2003-bit`, and do not allow the person who started a
run to approve it. Configure each registry trusted publisher for its exact
workflow path and the `main` ref. The `v*` tag ruleset prevents an existing
release tag from being changed or deleted.

Pull requests never receive publish permissions. Workflow and verification
changes are owned by the two release maintainers through
[`.github/CODEOWNERS`](.github/CODEOWNERS).

Install:

```sh
curl -fsSL https://cmux.com/coderouter/install.sh | sh
```
