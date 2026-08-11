# React Doctor (Zondax)

CLI-owned composite action that runs [`react-doctor`](https://react.doctor) with **mise-managed Node + CLI**, **pinned package version**, **configurable gate policy**, job summary, sticky PR comment, and commit status.

Unlike `millionco/react-doctor@v2`, this action does **not** re-host upstream JS for reviews/cache — it installs the scanner via **`mise`** (`node@…` + `npm:react-doctor@…`) and owns the CI glue (fail policy, comment, status).

## Usage

```yaml
name: React Doctor

on:
  pull_request:
    types: [opened, synchronize, reopened, ready_for_review]
  push:
    branches: [dev]

permissions:
  contents: read
  pull-requests: write
  statuses: write

jobs:
  react-doctor:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
        with:
          # Required for --scope changed (merge-base / base file content)
          fetch-depth: 0

      - uses: zondax/actions/react-doctor@v1
        with:
          # Pin the CLI (action default is already pinned)
          version: "0.9.11"
          # none | error | warning
          blocking: none
          # pr | always | never — when the workflow step fails
          fail_on: pr
```

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `directory` | `.` | Path to scan |
| `project` | _(empty)_ | Comma-separated workspace projects |
| `scope` | _(auto)_ | `full` \| `files` \| `changed` \| `lines`. Empty → `changed` on PRs, `full` otherwise |
| `base` | _(auto)_ | Base ref/SHA for diff scopes; empty → `pull_request.base.sha` |
| `blocking` | `none` | CLI gate: `none` (advisory), `error`, `warning` |
| `fail_on` | `pr` | Fail the job: `pr` only, `always`, or `never` |
| `version` | `0.9.11` | `react-doctor` version for mise (`npm:react-doctor@…`) |
| `node_version` | `24` | Node version installed via mise |
| `telemetry` | `true` | Score API / crash reporting (`false` → `--no-telemetry`) |
| `dead_code` | `true` | Dead-code analysis |
| `supply_chain` | `true` | Supply-chain analysis |
| `lint` | _(empty)_ | `true` / `false` / empty (CLI default) |
| `max_duration` | _(empty)_ | Seconds budget |
| `comment` | `true` | Sticky PR summary comment |
| `commit_status` | `true` | Commit status context `React Doctor` |
| `github_token` | `${{ github.token }}` | Token for comments/status |
| `working_directory` | `.` | Repo root for git base resolution |
| `extra_args` | _(empty)_ | Extra CLI flags (advanced) |

## Outputs

| Output | Description |
| --- | --- |
| `score` | 0–100 when available |
| `total-issues` | Diagnostic count |
| `error-count` / `warning-count` | Severity counts |
| `affected-files` | Files with findings |
| `ok` | Report success flag |
| `version` / `mode` | From JSON report |
| `report-file` | Path to JSON report |
| `exit-code` | CLI exit code |

## Gate policy

Two knobs (intentionally separate):

1. **`blocking`** — what the **CLI** treats as failure (`--blocking`).
2. **`fail_on`** — whether **this workflow step** propagates that exit code.

Examples:

- Advisory everywhere (current kunobi default): `blocking: none` (exit always 0).
- Fail PRs on new errors only: `blocking: error`, `fail_on: pr`, `scope: changed`.
- Health snapshot on `dev` without red mainline: `fail_on: pr` (push runs never fail).
- Hard gate on every event: `blocking: error`, `fail_on: always`.

## Permissions

| Permission | Why |
| --- | --- |
| `contents: read` | Checkout / git base |
| `pull-requests: write` | Sticky summary comment |
| `statuses: write` | Commit status |

## Toolchain

1. `jdx/mise-action@v2` — install mise (cached)
2. `mise use --global node@<node_version>`
3. `mise use --global npm:react-doctor@<version>`
4. Run the CLI; parse JSON; comment / status / gate

`version` accepts `0.9.11`, `react-doctor@0.9.11`, or `npm:react-doctor@0.9.11`.

## Notes

- Prefer `fetch-depth: 0` on checkout so `scope: changed` can resolve the merge base.
- Project config (`doctor.config.jsonc` / `doctor.config.*`) is honored by the CLI.
- Inline review comments are **not** implemented here (by design — keep the action small). Use the sticky summary + job summary instead; we can add reviews later if needed.
