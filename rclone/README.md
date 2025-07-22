# Rclone Action

Generic rclone operations with S3/MinIO backend support. Perfect for caching, syncing, file transfers, and cloud storage operations.

## Features

- 🚀 Fast parallel transfers with rclone
- 💾 S3/MinIO backend support
- 🗜️ Optional compression (for cache operations)
- 🔑 Flexible key patterns with restore keys (for cache operations)
- 📁 Multiple directory support
- ⚡ Multiple operation modes: copy (cache), sync, move, delete, size
- 🔄 Backward compatibility with existing cache workflows
- 🔁 Retry logic with exponential backoff for network failures
- 🛡️ Input validation and credential masking for security
- ⚙️ Configurable parallel transfers and bandwidth limiting
- 📊 Transfer statistics and structured logging
- 🧪 Dry-run mode and rclone filters support
- 📈 Progress indicators and operation summaries
- ✅ Checksum verification for data integrity

## Supported Operations

### Copy (Cache)
High-performance caching with restore/save modes and fallback keys.

### Sync
Make source and destination identical, deleting files not in source.

### Move
Move files from source to destination, deleting source after successful transfer.

### Delete
Delete files/directories from remote storage.

### Size
Get the size and file count of remote directories.

## Usage

### Cache Operations (Copy)

#### Basic Cache Example

```yaml
- name: Cache dependencies
  uses: ./rclone
  with:
    operation: copy  # or omit for default
    key: deps-${{ runner.os }}-${{ hashFiles('**/package-lock.json') }}
    paths: |
      node_modules
      ~/.npm
    endpoint: https://s3.amazonaws.com
    bucket: my-cache-bucket
    access-key: ${{ secrets.S3_ACCESS_KEY }}
    secret-key: ${{ secrets.S3_SECRET_KEY }}
```

#### Cache with Restore Keys

```yaml
- name: Cache with fallback
  id: cache
  uses: ./rclone
  with:
    operation: copy
    key: build-${{ runner.os }}-${{ github.sha }}
    restore-keys: |
      build-${{ runner.os }}-
      build-
    paths: |
      dist
      .cache
    endpoint: ${{ secrets.MINIO_ENDPOINT }}
    bucket: ${{ secrets.CACHE_BUCKET }}
    access-key: ${{ secrets.MINIO_ACCESS_KEY }}
    secret-key: ${{ secrets.MINIO_SECRET_KEY }}
```

#### Separate Restore/Save Steps

```yaml
- name: Restore cache
  id: cache-restore
  uses: ./rclone
  with:
    operation: copy
    mode: restore
    key: cargo-${{ runner.os }}-${{ hashFiles('**/Cargo.lock') }}
    paths: |
      ~/.cargo/registry
      ~/.cargo/git
      target
    endpoint: ${{ secrets.S3_ENDPOINT }}
    bucket: ${{ secrets.S3_BUCKET }}
    access-key: ${{ secrets.S3_ACCESS_KEY }}
    secret-key: ${{ secrets.S3_SECRET_KEY }}

- name: Build project
  run: cargo build --release

- name: Save cache
  if: steps.cache-restore.outputs.cache-hit != 'true'
  uses: ./rclone
  with:
    operation: copy
    mode: save
    key: cargo-${{ runner.os }}-${{ hashFiles('**/Cargo.lock') }}
    paths: |
      ~/.cargo/registry
      ~/.cargo/git
      target
    endpoint: ${{ secrets.S3_ENDPOINT }}
    bucket: ${{ secrets.S3_BUCKET }}
    access-key: ${{ secrets.S3_ACCESS_KEY }}
    secret-key: ${{ secrets.S3_SECRET_KEY }}
```

### Sync Operations

```yaml
- name: Sync build artifacts
  uses: ./rclone
  with:
    operation: sync
    source: ./dist
    destination: "remote:${{ secrets.S3_BUCKET }}/artifacts/"
    endpoint: ${{ secrets.S3_ENDPOINT }}
    bucket: ${{ secrets.S3_BUCKET }}
    access-key: ${{ secrets.S3_ACCESS_KEY }}
    secret-key: ${{ secrets.S3_SECRET_KEY }}
```

### Move Operations

```yaml
- name: Move files to archive
  uses: ./rclone
  with:
    operation: move
    source: ./temp-files
    destination: "remote:${{ secrets.S3_BUCKET }}/archive/"
    endpoint: ${{ secrets.S3_ENDPOINT }}
    bucket: ${{ secrets.S3_BUCKET }}
    access-key: ${{ secrets.S3_ACCESS_KEY }}
    secret-key: ${{ secrets.S3_SECRET_KEY }}
```

### Delete Operations

```yaml
- name: Clean up old artifacts
  uses: ./rclone
  with:
    operation: delete
    source: "remote:${{ secrets.S3_BUCKET }}/old-artifacts/"
    endpoint: ${{ secrets.S3_ENDPOINT }}
    bucket: ${{ secrets.S3_BUCKET }}
    access-key: ${{ secrets.S3_ACCESS_KEY }}
    secret-key: ${{ secrets.S3_SECRET_KEY }}
```

### Size Operations

```yaml
- name: Check storage usage
  id: storage-check
  uses: ./rclone
  with:
    operation: size
    source: "remote:${{ secrets.S3_BUCKET }}/"
    endpoint: ${{ secrets.S3_ENDPOINT }}
    bucket: ${{ secrets.S3_BUCKET }}
    access-key: ${{ secrets.S3_ACCESS_KEY }}
    secret-key: ${{ secrets.S3_SECRET_KEY }}

- name: Show storage stats
  run: |
    echo "Total bytes: ${{ steps.storage-check.outputs.bytes-transferred }}"
    echo "Operation result: ${{ steps.storage-check.outputs.operation-result }}"
```

## Inputs

| Input | Description | Required | Default | Operations |
|-------|-------------|----------|---------|------------|
| `operation` | Operation type: `copy`, `sync`, `move`, `delete`, `size` | No | `copy` | All |
| `source` | Source path/remote | No* | - | sync, move, delete, size |
| `destination` | Destination path/remote | No* | - | sync, move |
| `mode` | Cache mode: `restore`, `save`, or `restore-save` | No | `restore-save` | copy only |
| `key` | Unique cache key | No* | - | copy only |
| `paths` | Directories to cache (YAML list or space-separated) | No* | - | copy only |
| `restore-keys` | Fallback keys for cache restore | No | - | copy only |
| `endpoint` | S3/MinIO endpoint URL | Yes | - | All |
| `bucket` | S3/MinIO bucket name | Yes | - | All |
| `access-key` | S3/MinIO access key | Yes | - | All |
| `secret-key` | S3/MinIO secret key | Yes | - | All |
| `region` | S3 region | No | `us-east-1` | All |
| `fail-on-miss` | Fail if cache miss on restore | No | `false` | copy only |
| `compression` | Enable compression | No | `true` | copy only |
| `progress` | Show progress during transfers | No | `true` | All |
| `max-retries` | Maximum number of retry attempts | No | `3` | All |
| `retry-delay` | Initial delay between retries (seconds) | No | `5` | All |
| `timeout` | Timeout for operations (seconds) | No | `300` | All |
| `parallel-transfers` | Number of parallel file transfers | No | `4` | All |
| `bandwidth-limit` | Bandwidth limit (e.g., 10M, 1G) | No | - | All |
| `checkers` | Number of checkers in parallel | No | `8` | All |
| `dry-run` | Show what would be done without doing it | No | `false` | All |
| `include-filters` | Include filters (YAML list or space-separated) | No | - | All |
| `exclude-filters` | Exclude filters (YAML list or space-separated) | No | - | All |
| `checksum-verify` | Verify checksums during transfers | No | `true` | All |

*Required depending on operation type

## Outputs

| Output | Description | Operations |
|--------|-------------|------------|
| `cache-hit` | Whether cache was restored (`true`/`false`) | copy only |
| `cache-key` | The actual key used for restore | copy only |
| `operation-result` | Result of the operation (`success`/`failed`) | All |
| `bytes-transferred` | Number of bytes transferred | All |
| `transfer-duration` | Duration of the transfer in seconds | All |
| `transfer-rate` | Transfer rate in bytes per second | All |
| `files-transferred` | Number of files transferred | All |
| `errors` | Number of errors encountered | All |

## Backward Compatibility

This action maintains full backward compatibility with existing cache workflows. You can:

1. **Use without specifying operation** - defaults to `copy` (cache mode)
2. **Use existing cache parameters** - all cache inputs work as before
3. **Gradually migrate** - update workflows at your own pace

```yaml
# Old usage (still works)
- uses: ./rclone
  with:
    key: my-cache-key
    paths: node_modules
    # ... other cache parameters

# New explicit usage
- uses: ./rclone
  with:
    operation: copy
    key: my-cache-key
    paths: node_modules
    # ... other cache parameters
```

## S3/MinIO Setup

### AWS S3

```yaml
endpoint: https://s3.amazonaws.com
region: us-east-1  # or your region
bucket: my-cache-bucket
```

### MinIO

```yaml
endpoint: https://minio.example.com
region: us-east-1  # MinIO requires this
bucket: github-cache
```

### DigitalOcean Spaces

```yaml
endpoint: https://nyc3.digitaloceanspaces.com
region: us-east-1
bucket: my-space-name
```

## Advanced Features

### Performance Optimization

```yaml
- name: High-performance sync with custom settings
  uses: ./rclone
  with:
    operation: sync
    source: ./large-dataset
    destination: "remote:${{ secrets.S3_BUCKET }}/data/"
    parallel-transfers: 8
    bandwidth-limit: 50M
    checkers: 16
    endpoint: ${{ secrets.S3_ENDPOINT }}
    bucket: ${{ secrets.S3_BUCKET }}
    access-key: ${{ secrets.S3_ACCESS_KEY }}
    secret-key: ${{ secrets.S3_SECRET_KEY }}
```

### Filtering and Dry-run

```yaml
- name: Sync with filters and dry-run
  uses: ./rclone
  with:
    operation: sync
    source: ./project
    destination: "remote:${{ secrets.S3_BUCKET }}/filtered/"
    dry-run: true
    include-filters: |
      *.txt
      *.md
    exclude-filters: |
      node_modules/**
      .git/**
    endpoint: ${{ secrets.S3_ENDPOINT }}
    bucket: ${{ secrets.S3_BUCKET }}
    access-key: ${{ secrets.S3_ACCESS_KEY }}
    secret-key: ${{ secrets.S3_SECRET_KEY }}
```

### Reliability and Error Handling

```yaml
- name: Reliable transfer with retry logic
  uses: ./rclone
  with:
    operation: copy
    key: reliable-cache-${{ github.sha }}
    paths: ./dist
    max-retries: 5
    retry-delay: 10
    timeout: 600
    checksum-verify: true
    endpoint: ${{ secrets.S3_ENDPOINT }}
    bucket: ${{ secrets.S3_BUCKET }}
    access-key: ${{ secrets.S3_ACCESS_KEY }}
    secret-key: ${{ secrets.S3_SECRET_KEY }}
```

## Performance Tips

### For Cache Operations
1. **Use compression** for text-heavy caches (source code, dependencies)
2. **Disable compression** for already-compressed files (images, binaries)
3. **Use specific keys** to avoid unnecessary cache updates
4. **Order restore-keys** from most specific to least specific

### For All Operations
1. **Use same region** as your runners for faster transfers
2. **Enable progress** for visibility into long-running operations
3. **Monitor bytes-transferred** output for performance analysis
4. **Increase parallel-transfers** for large file counts
5. **Use bandwidth-limit** to avoid overwhelming network connections
6. **Enable checksum verification** for critical data integrity

## Security

- Store credentials as secrets
- Use IAM policies to limit bucket access
- Consider bucket lifecycle policies for cache expiration
- Enable S3 bucket versioning for recovery
- Use least-privilege access keys

## Example: Multi-operation Workflow

```yaml
jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      # Cache dependencies
      - name: Cache dependencies
        uses: ./rclone
        with:
          key: deps-${{ runner.os }}-${{ hashFiles('**/package-lock.json') }}
          paths: |
            node_modules
            ~/.npm
          endpoint: ${{ secrets.S3_ENDPOINT }}
          bucket: ${{ secrets.CACHE_BUCKET }}
          access-key: ${{ secrets.S3_ACCESS_KEY }}
          secret-key: ${{ secrets.S3_SECRET_KEY }}
      
      - name: Build project
        run: npm run build
      
      # Sync build artifacts
      - name: Deploy to S3
        uses: ./rclone
        with:
          operation: sync
          source: ./dist
          destination: "remote:${{ secrets.DEPLOY_BUCKET }}/app/"
          endpoint: ${{ secrets.S3_ENDPOINT }}
          bucket: ${{ secrets.DEPLOY_BUCKET }}
          access-key: ${{ secrets.S3_ACCESS_KEY }}
          secret-key: ${{ secrets.S3_SECRET_KEY }}
      
      # Clean up old builds
      - name: Clean up old artifacts
        uses: ./rclone
        with:
          operation: delete
          source: "remote:${{ secrets.DEPLOY_BUCKET }}/old-builds/"
          endpoint: ${{ secrets.S3_ENDPOINT }}
          bucket: ${{ secrets.DEPLOY_BUCKET }}
          access-key: ${{ secrets.S3_ACCESS_KEY }}
          secret-key: ${{ secrets.S3_SECRET_KEY }}
```

## Migration Guide

### From `rclone-cache` to `rclone`

1. Update action path: `./rclone-cache` → `./rclone`
2. Optionally add `operation: copy` for clarity
3. All existing inputs and outputs work unchanged
4. New outputs (`operation-result`, `bytes-transferred`) are available

### Example Migration

```yaml
# Before
- uses: ./rclone-cache
  with:
    key: my-key
    paths: node_modules

# After (minimal change)
- uses: ./rclone
  with:
    key: my-key
    paths: node_modules

# After (explicit)
- uses: ./rclone
  with:
    operation: copy
    key: my-key
    paths: node_modules
```