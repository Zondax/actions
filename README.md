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

### setup-node-env

Setup Node.js with package manager (npm, yarn, pnpm, or bun) and install dependencies.

**Usage:**
```yaml
- uses: zondax/zondax-actions/setup-node-env@v1
  with:
    node_version: '20'
    package_manager: 'pnpm'
    package_manager_version: '8.0.0'
    autoinit_env: true
```

**Inputs:**
- `node_version`: Node.js version to install (default: lts/*)
- `package_manager`: Package manager to use - npm, yarn, pnpm, or bun (default: npm)
- `package_manager_version`: Package manager version (default: latest)
- `install_deps`: Install dependencies after setup (default: true)
- `working_directory`: Working directory for package operations (default: .)
- `cache_dependencies`: Cache dependencies (default: true)
- `autoinit_env`: Run env:init:ci script after installing dependencies (default: false)

**Outputs:**
- `pm`: Package manager command (e.g., 'pnpm')
- `pm_run`: Package manager run command (e.g., 'pnpm run')
- `cache_hit`: Whether the cache was hit

### gcp-wif-auth

Authenticate with Google Cloud using Workload Identity Federation with optional JWT debugging.

**Usage:**
```yaml
- uses: zondax/zondax-actions/gcp-wif-auth@v1
  with:
    workload_identity_provider: ${{ vars.PULUMI_DEPLOY_WIF_PROVIDER }}
    project_id: ${{ vars.PULUMI_GCP_PROJECT_ID }}
    log_jwt_info: true
```

**Inputs:**
- `workload_identity_provider`: Workload Identity Provider resource name (required)
- `project_id`: GCP Project ID
- `service_account`: Service account email to impersonate
- `audience`: Audience for the OIDC token
- `setup_gcloud`: Install and configure gcloud SDK (default: true)
- `gcloud_version`: Version of gcloud SDK to install (default: latest)
- `gcloud_components`: Additional gcloud components to install (comma-separated)
- `log_jwt_info`: Log JWT token information for debugging (default: true)
- `verify_authentication`: Verify authentication by running gcloud commands (default: true)
- `export_credentials`: Export credentials to environment (default: true)

**Outputs:**
- `credentials_path`: Path to the generated credentials file
- `access_token`: Access token for authenticated requests
- `project_id`: GCP Project ID

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