# Migration guide — Zondax Actions (2026-08 / post #23–#28)

Use this when upgrading consumer repos from **`v1.2.0` / floating `v1` (pre-hardening)** to a release that includes:

| PR | Change |
| --- | --- |
| #23 | `setup-mise`, rewritten `setup-node-env` |
| #24 | `gcp-wif-auth` single auth step |
| #25 | `checkout-with-app` → `actions/checkout@v7` |
| #26 | `sign-*` dual snake/kebab inputs, shared mise/WIF |
| #27 | new `react-doctor` action |
| #28 | docs, Dependabot, actionlint |

**Target ref:** prefer a **semver tag** (e.g. `v1.3.0`) once cut. Floating `v1` only after maintainers move it to that tag.

```bash
# Until floating v1 is moved, pin explicitly:
uses: zondax/actions/setup-node-env@v1.3.0
# or a commit SHA on main
uses: zondax/actions/setup-node-env@2e1cc10
```

---

## 0. Consumer checklist (every repo)

- [ ] **Pin or refresh the action ref**  
  - If you use `@v1` and maintainers have moved `v1` → you get everything automatically (review diffs below first).  
  - If `v1` is still on `v1.2.0`, either wait for the tag move or pin `@v1.3.0` / SHA.

- [ ] **Search call sites**
  ```bash
  rg -n 'zondax/actions/' .github
  ```

- [ ] **Map each action** to the section below and apply the listed changes.

- [ ] **CI smoke** after the bump: one PR that only changes action refs + required input tweaks.

- [ ] **Secret/OIDC jobs** (WIF, signing): run a real or `workflow_dispatch` path once after upgrade.

---

## 1. Breaking / behavioral changes

### 1.1 `setup-node-env` — **read this first**

| Before (≤ v1.2.x) | After (#23+) |
| --- | --- |
| Default `node_version`: **`22`** (docs sometimes said 20 / `lts/*`) | Default **`24`** |
| Installed **yarn + pnpm + bun + typescript** every time | Installs **only** `package_manager` (+ node) |
| Always verified `tsc` on PATH | `tsc` only if `install_typescript: true` |
| Inputs `cache_dependencies`, output `cache_hit` | **Removed** (they never worked) |
| `pnpm_version` default `latest` | Default **`10`** (mise `github:pnpm/pnpm@10`) |
| `yarn_version` / `bun_version` default `latest` | Defaults **`4`** / **`1`** |

**Migrate**

```yaml
# Before
- uses: zondax/actions/setup-node-env@v1
  with:
    node_version: '20'          # EOL — stop doing this
    package_manager: 'pnpm'
    # implicit: all PMs + tsc

# After
- uses: zondax/actions/setup-node-env@v1.3.0   # or @v1 after float
  with:
    node_version: '24'          # or '22' if you must stay on Maintenance LTS
    package_manager: 'pnpm'
    pnpm_version: '10'          # optional; 10 is default
    install_typescript: true    # ONLY if a later step needs tsc
    # delete: cache_dependencies
```

**If a job used `steps.setup.outputs.cache_hit`:** remove it; there is no cache hit signal from this action.

**Node policy**

| Major | Status |
| --- | --- |
| ≤ 20 | Unsupported (EOL). Action warns. |
| 22 | Supported |
| 24 | Default / recommended |

---

### 1.2 `gcp-wif-auth`

| Before | After (#24+) |
| --- | --- |
| Four nearly identical auth steps | **One** `google-github-actions/auth` step |
| `gcloud_version` default `latest` | Default pinned (e.g. **`519.0.0`**) — override if you need newer |
| `log_jwt_info` default `true` | Default **`false`** (JWT dump reserved / quieter logs) |

**Call-site inputs are unchanged** (`workload_identity_provider`, `project_id`, `service_account`, `token_format`, …).

```yaml
# Usually no change required:
- uses: zondax/actions/gcp-wif-auth@v1.3.0
  with:
    workload_identity_provider: ${{ vars.WIF_PROVIDER }}
    project_id: ${{ vars.GCP_PROJECT_ID }}
    service_account: ${{ vars.GCP_SA }}   # empty string still OK for principal-set
    token_format: access_token            # when you need access_token output
```

**Note:** still on **google-github-actions/auth@v2** (not v3) so empty `service_account` principal-set keeps working.

---

### 1.3 `checkout-with-app`

| Before | After (#25+) |
| --- | --- |
| `actions/checkout@v6` | **`@v7`** |
| App token interpolated into shell for git rewrite | Token via **`env`** (safer) |

**Inputs unchanged.** No consumer YAML change expected beyond the action ref bump.

---

### 1.4 `sign-linux-binary` / `sign-macos-binary` / `sign-windows-binary`

| Before | After (#26+) |
| --- | --- |
| kebab-case only (`target-path`, …) | **snake_case preferred**; **kebab-case aliases still work** |
| Linux: curl-install mise | **`setup-mise`** + `github:kunobi-pgp-kms` |
| macOS: direct `google-github-actions/auth` | **`./gcp-wif-auth`** (same inputs) |
| Windows: `setup-java@v4` | **`@v5`** |
| Outputs mostly kebab-case | snake_case + kebab-case aliases |

**Migrate (non-urgent):** keep kebab-case today; prefer snake_case on next edit.

```yaml
# Still valid
- uses: zondax/actions/sign-linux-binary@v1.3.0
  with:
    target-path: dist/app.tar.gz
    workload-identity-provider: ${{ vars.PGP_SIGN_WIF_PROVIDER }}
    # ...

# Preferred
- uses: zondax/actions/sign-linux-binary@v1.3.0
  with:
    target_path: dist/app.tar.gz
    workload_identity_provider: ${{ vars.PGP_SIGN_WIF_PROVIDER }}
    gcp_project_id: ${{ vars.PGP_SIGN_GCP_PROJECT_ID }}
    signer_token: ${{ steps.app.outputs.token }}
    kms_key: ${{ vars.PGP_SIGN_KMS_KEY_VERSION }}
    cert_base64: ${{ secrets.PGP_CERT_BASE64 }}
```

**Output rename (optional):** prefer `signature_path` / `cert_fingerprint` / `os_code_signature`; kebab aliases remain.

---

## 2. Non-breaking / additive

### 2.1 New: `setup-mise`

Canonical mise bootstrap. Consumers usually **do not** call this directly — other actions compose it. Use it when a job only needs mise:

```yaml
- uses: zondax/actions/setup-mise@v1.3.0
- run: mise use --global node@24 && mise install
```

### 2.2 New: `react-doctor`

Replaces ad-hoc `millionco/react-doctor@v2` (or similar) with a Zondax-owned gate.

```yaml
permissions:
  contents: read
  pull-requests: write   # sticky comment
  statuses: write        # commit status

jobs:
  react-doctor:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
        with:
          fetch-depth: 0   # required for scope: changed
      - uses: zondax/actions/react-doctor@v1.3.0
        with:
          version: '0.9.11'     # pin the CLI
          blocking: none        # none | error | warning
          fail_on: pr           # pr | always | never
          # scope: empty → changed on PRs, full on push
```

See [`react-doctor/README.md`](./react-doctor/README.md).

**Kunobi note:** if the workflow still points at `@main` or `millionco/react-doctor`, switch to the tagged action after release.

### 2.3 Unchanged (for this train)

| Action | Notes |
| --- | --- |
| `setup-ubuntu-packages` | No API change in this train |
| `release-hold` | No change in #23–#28. Still GNU `date -d`; callers may set `GH_TOKEN` (see open/stale #10) |
| `rclone` | Unchanged; CI still disabled — best-effort |

---

## 3. Per-action migration table

| Action | Must change YAML? | Recommended |
| --- | --- | --- |
| `setup-node-env` | **Yes if** you relied on tsc, cache_hit, Node 20, or multi-PM | Pin node 24; set `install_typescript` if needed |
| `gcp-wif-auth` | No | Bump ref; optionally pin `gcloud_version` |
| `checkout-with-app` | No | Bump ref |
| `sign-*` | No (aliases) | Move to snake_case when touching the workflow |
| `setup-mise` | N/A (new) | Optional direct use |
| `react-doctor` | **Yes** if adopting | Replace upstream react-doctor action |
| `release-hold` | No for this train | Keep `GH_TOKEN` at call site for now |
| `setup-ubuntu-packages` | No | Bump ref only |

---

## 4. Suggested rollout order (monorepo / org)

1. **Tag release** in `Zondax/actions` (`v1.3.0` or next) — include #23–#28.
2. **Move floating `v1`** only after a smoke on one consumer (or leave `v1` and force consumers to pin `v1.3.0` first).
3. **Pilot 1 — low risk:** `checkout-with-app`, `gcp-wif-auth` ref bumps only.
4. **Wave 2 — node:** `setup-node-env` with explicit `node_version` + `install_typescript` where needed.
5. **Wave 3 — signing:** ref bump (kebab-case OK); optional snake_case cleanup.
6. **Wave 4 — quality:** adopt `react-doctor` where React CI matters.
7. **Close the loop:** search for `node_version: '20'`, `cache_dependencies`, `cache_hit`, `millionco/react-doctor`.

---

## 5. Example: full before/after (typical app CI)

```yaml
# BEFORE
- uses: zondax/actions/checkout-with-app@v1
  with:
    github_app_auth: true
    app_id: ${{ secrets.APP_ID }}
    app_pem: ${{ secrets.APP_PEM }}
- uses: zondax/actions/setup-node-env@v1
  with:
    node_version: '20'
    package_manager: pnpm
- uses: zondax/actions/gcp-wif-auth@v1
  with:
    workload_identity_provider: ${{ vars.WIF }}
    project_id: ${{ vars.PROJECT }}

# AFTER
- uses: zondax/actions/checkout-with-app@v1.3.0
  with:
    github_app_auth: true
    app_id: ${{ secrets.APP_ID }}
    app_pem: ${{ secrets.APP_PEM }}
- uses: zondax/actions/setup-node-env@v1.3.0
  with:
    node_version: '24'
    package_manager: pnpm
    # install_typescript: true   # only if needed
- uses: zondax/actions/gcp-wif-auth@v1.3.0
  with:
    workload_identity_provider: ${{ vars.WIF }}
    project_id: ${{ vars.PROJECT }}
```

---

## 6. Finding consumers (maintainers)

```bash
# GitHub org search (web or gh)
gh search code 'zondax/actions/' --owner Zondax --filename '*.yml'
gh search code 'zondax/actions/' --owner Zondax --filename '*.yaml'
```

Track migrations as issues per repo, e.g. `chore(ci): migrate zondax/actions to v1.3.0`.

---

## 7. Rollback

- Pin the previous tag: `zondax/actions/<name>@v1.2.0` (or the pre-move `v1` commit).
- `setup-node-env` API removals (`cache_hit`) cannot be rolled back by config — remove consumer references before upgrading, or keep the old pin until call sites are clean.

---

## 8. Related docs

- [README.md](./README.md) — current action index and conventions  
- [CONTRIBUTING.md](./CONTRIBUTING.md) — adding actions / Node policy  
- [react-doctor/README.md](./react-doctor/README.md) — gate knobs  
- Issues #13–#21 — design rationale for this train

## 9. Hotfix: nested composite paths (v1.3.0 → v1.3.1)

`v1.3.0` used relative sibling paths (`uses: ./setup-mise`) inside composites.
When a consumer runs `zondax/actions/setup-node-env@v1`, GitHub resolves `./…`
against the **consumer workspace**, not the actions repo — CI fails with:

```text
Can't find 'action.yml' under '.../<consumer>/setup-mise'
```

**v1.3.1** switches those to `zondax/actions/setup-mise@v1` / `gcp-wif-auth@v1`.
No consumer YAML change required beyond picking up `@v1` / `@v1.3.1`.

