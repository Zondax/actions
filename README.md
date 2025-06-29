# Zondax GitHub Actions

A collection of reusable composite actions for Zondax projects.

## Available Actions

### checkout-with-app

Checkout repository with optional GitHub App authentication and git configuration.

**Usage:**
```yaml
- uses: zondax/zondax-actions/checkout-with-app@v1
  with:
    github_app_auth: true
    github_app_repos: |
      owner/repo1
      owner/repo2
    app_id: ${{ secrets.APP_ID }}
    app_pem: ${{ secrets.APP_PEM }}
```

**Inputs:**
- `github_app_auth`: Use GitHub App Token (default: false)
- `github_app_repos`: Additional repositories to access (one per line)
- `checkout_submodules`: Checkout submodules (default: true)
- `fetch_depth`: Number of commits to fetch. 0 fetches all history (default: 0)
- `ref`: The branch, tag or SHA to checkout
- `use_sudo`: Use sudo for git config command (default: false)
- `patch_git_config`: Add safe.directory to git config (default: true)
- `app_id`: GitHub App ID
- `app_pem`: GitHub App PEM

## Usage in Reusable Workflows

Update your reusable workflows in `_workflows` repository:

```yaml
jobs:
  my-job:
    steps:
      - name: Checkout with GitHub App
        uses: zondax/zondax-actions/checkout-with-app@v1
        with:
          github_app_auth: ${{ inputs.github_app_auth }}
          github_app_repos: ${{ inputs.github_app_repos }}
          checkout_submodules: ${{ inputs.checkout_submodules }}
          ref: ${{ github.event.pull_request.head.sha }}
          app_id: ${{ secrets.app_id }}
          app_pem: ${{ secrets.app_pem }}
```

## Contributing

1. Create a new directory for your action
2. Add an `action.yml` file
3. Document the action in this README
4. Submit a PR

## License

Apache License 2.0