# Contributing to Zondax/actions

## Adding an action

1. Create `my-action/action.yml` (composite).
2. Prefer **snake_case** inputs; add kebab-case aliases only if migrating existing call sites.
3. Bootstrap toolchains with `./setup-mise`, not ad-hoc curl installers.
4. Compose siblings with relative paths (`./gcp-wif-auth`) so a single tag is consistent.
5. Document the action in the root `README.md`.
6. Add a smoke test under `.github/workflows/` when the action is pure logic / no secrets.

## Node versions

- Default and recommend **24**.
- CI-test **22** and **24**.
- Never document or default to **20** (EOL).

## Releasing

See root README “Releasing”. Maintainers: after merge to `main`, cut `vX.Y.Z` and move floating `v1`.
