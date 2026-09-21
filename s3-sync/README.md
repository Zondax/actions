# s3-sync

Copy or sync a local directory or an S3 prefix to an S3 prefix. Works with
Cloudflare R2, AWS S3, and Ceph RGW (any S3 API). rclone must already be on
`PATH`.

```yaml
- uses: zondax/actions/s3-sync@v1
  with:
    source: dist/
    dest: staging/${{ github.run_id }}/
    bucket: ${{ vars.BUCKET }}
    endpoint: ${{ vars.S3_ENDPOINT }}
    access_key_id: ${{ secrets.S3_ACCESS_KEY_ID }}
    secret_access_key: ${{ secrets.S3_SECRET_ACCESS_KEY }}
    provider: Other          # Cloudflare | AWS | Other | Ceph | Minio
    region: us-east-1        # auto for R2
    mode: sync
```

S3 to a local directory (dest starts with `./` or `/`):

```yaml
- uses: zondax/actions/s3-sync@v1
  with:
    source: s3:${{ vars.BUCKET }}/staging/${{ github.run_id }}/linux/
    dest: ./platform-artifacts/
    bucket: ${{ vars.BUCKET }}
    endpoint: ${{ vars.S3_ENDPOINT }}
    access_key_id: ${{ secrets.S3_ACCESS_KEY_ID }}
    secret_access_key: ${{ secrets.S3_SECRET_ACCESS_KEY }}
    mode: copy
```

S3 to S3 (same credentials):

```yaml
- uses: zondax/actions/s3-sync@v1
  with:
    source: s3:${{ vars.BUCKET }}/staging/${{ github.run_id }}/
    dest: screenshots/${{ inputs.version }}/
    bucket: ${{ vars.BUCKET }}
    endpoint: ${{ vars.S3_ENDPOINT }}
    access_key_id: ${{ secrets.S3_ACCESS_KEY_ID }}
    secret_access_key: ${{ secrets.S3_SECRET_ACCESS_KEY }}
    mode: copy
```

`copy` does not delete extras at the destination. `sync` does.

The `rclone/` action in this repo is a cache helper; its `copy` operation is
not `rclone copy`. Use `s3-sync` for object transfers.
