# Zondax GitHub Actions

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

Reusable **composite** GitHub Actions for Zondax / Kunobi CI. Prefer these over ad-hoc workflow copy-paste.

**Repository:** [github.com/Zondax/actions](https://github.com/Zondax/actions)

**Upgrading consumers?** See **[MIGRATION.md](./MIGRATION.md)** for the post-#23–#28 train (setup-mise, setup-node-env, WIF, sign-*, react-doctor).

## Conventions

| Topic | Rule |
| --- | --- |
| Toolchains | **mise first** via `setup-mise` (`jdx/mise-action@v4`) |
| Input names | **snake_case** preferred; kebab-case aliases kept where call sites already exist |
| Node | **24** recommended, **22** supported/tested, **20 EOL** (do not use) |
| Pins | Prefer pinned tool versions over `latest` |
| Same-repo composition | Composites call siblings with `./name` so one tag is atomic |
| Releases | Tag `vX.Y.Z`, move floating `v1`, publish GitHub Release notes |

## Available actions

### setup-mise

Canonical mise bootstrap (cache + shims on `PATH`).

```yaml
- uses: zondax/actions/setup-mise@v1
```

### setup-node-env

Node + **one** package manager via mise. Optionally install deps / run `env:init:ci`.

```yaml
- uses: zondax/actions/setup-node-env@v1
  with:
    node_version: '24'
    package_manager: 'pnpm'
    pnpm_version: '10'
    install_deps: true
```

| Input | Default | Notes |
| --- | --- | --- |
| `node_version` | `24` | Warns if major ≤ 20 |
| `package_manager` | `npm` | `npm` \| `yarn` \| `pnpm` \| `bun` |
| `pnpm_version` | `10` | Uses `github:pnpm/pnpm` backend |
| `install_typescript` | `false` | Opt-in `tsc` |
| `install_deps` | `true` | |
| `autoinit_env` | `false` | Runs `env:init:ci` |

Outputs: `pm`, `pm_run`, `node_version`.

### checkout-with-app

Checkout with optional GitHub App token + `safe.directory` hardening.

```yaml
- uses: zondax/actions/checkout-with-app@v1
  with:
    github_app_auth: true
    app_id: ${{ secrets.APP_ID }}
    app_pem: ${{ secrets.APP_PEM }}
    fetch_depth: 0
```

### setup-ubuntu-packages

Optional Init7/mirror config + apt install helpers.

```yaml
- uses: zondax/actions/setup-ubuntu-packages@v1
  with:
    packages: |
      - build-essential
      - pkg-config
```

### gcp-wif-auth

Workload Identity Federation via a **single** `google-github-actions/auth` step.

```yaml
- uses: zondax/actions/gcp-wif-auth@v1
  with:
    workload_identity_provider: ${{ vars.WIF_PROVIDER }}
    project_id: ${{ vars.GCP_PROJECT_ID }}
    service_account: ${{ vars.GCP_SA }}   # optional
    token_format: access_token            # when you need access_token output
```

### release-hold

Time-based gate before publishing (artifact / release age).

```yaml
- uses: zondax/actions/release-hold@v1
  with:
    hold_period: '30'
    anchor: release-asset
```

### react-doctor

CLI-owned [React Doctor](https://react.doctor) scan (mise-installed, configurable gate).

```yaml
- uses: actions/checkout@v7
  with:
    fetch-depth: 0
- uses: zondax/actions/react-doctor@v1
  with:
    version: '0.9.11'
    blocking: none    # none | error | warning
    fail_on: pr       # pr | always | never
```

See [`react-doctor/README.md`](./react-doctor/README.md).

### sign-linux-binary / sign-macos-binary / sign-windows-binary

Platform code-signing (GCP KMS / Secret Manager / jsign / rcodesign).

- Prefer **snake_case** inputs; **kebab-case aliases** still work for existing Kunobi workflows.
- Linux/macOS compose `./gcp-wif-auth` + `./setup-mise` from the same tag.
- See each action’s `action.yml` for inputs.

```yaml
# Linux OpenPGP (KMS)
- uses: zondax/actions/sign-linux-binary@v1
  with:
    target_path: dist/app.tar.gz
    # or legacy: target-path: dist/app.tar.gz
    workload_identity_provider: ${{ vars.PGP_SIGN_WIF_PROVIDER }}
    gcp_project_id: ${{ vars.PGP_SIGN_GCP_PROJECT_ID }}
    signer_token: ${{ steps.app.outputs.token }}
    kms_key: ${{ vars.PGP_SIGN_KMS_KEY_VERSION }}
    cert_base64: ${{ secrets.PGP_CERT_BASE64 }}
```

### rclone

S3/MinIO rclone helper (cache/copy/sync). CI workflow is currently **disabled** (`test-rclone.yml.disabled`) — treat as best-effort until re-enabled. See [`rclone/README.md`](./rclone/README.md).

## Node support matrix

| Major | Status |
| --- | --- |
| ≤20 | **Unsupported (EOL)** — examples removed; `setup-node-env` warns |
| 22 | Supported / CI-tested (Maintenance LTS) |
| 24 | Supported / CI-tested (**recommended**) |

## Releasing

1. Land changes on `main`.
2. Tag `vX.Y.Z` (semver; breaking input removals = major if we ever leave v1).
3. Move the floating major: `git tag -f v1 vX.Y.Z && git push -f origin v1` (maintainers only).
4. Publish a GitHub Release with notes listing new/changed actions.
5. Consumers on `@v1` pick up the floating major; pin `@vX.Y.Z` for hermetic builds.

## Development

```bash
git clone git@github.com:Zondax/actions.git
cd actions
# Local composite paths work in workflows under .github/workflows/
```

CI:

- `install-node.yml` — matrix Node 22/24 × package managers, setup-mise, release-hold smoke, react-doctor parser
- `install-ubuntu.yml` — package helper
- `actionlint.yml` — workflow lint

## Troubleshooting

| Issue | Fix |
| --- | --- |
| Node version conflicts | Pin `node_version: '24'` |
| pnpm install fails in mise | Uses `github:pnpm/pnpm@…` backend by design |
| WIF / empty service account | Leave `service_account` empty for principal-set bindings |
| React Doctor shallow checkout | Use `fetch-depth: 0` on checkout for `scope: changed` |
