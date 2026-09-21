# r2-sync

Copy or sync a local directory or an R2 prefix to an R2 prefix. For the
job-to-job bus (stage then publish) instead of GitHub Actions artifacts.

rclone must already be on `PATH` (mise pin, or the runner image).

```yaml
- uses: zondax/actions/r2-sync@v1
  with:
    source: dist/
    dest: staging/${{ github.run_id }}/
    bucket: ${{ vars.R2_BUCKET }}
    endpoint: https://${{ vars.R2_ACCOUNT_ID }}.r2.cloudflarestorage.com
    access_key_id: ${{ secrets.R2_ACCESS_KEY_ID }}
    secret_access_key: ${{ secrets.R2_SECRET_ACCESS_KEY }}
    mode: sync
```

R2 to R2 (same credentials):

```yaml
- uses: zondax/actions/r2-sync@v1
  with:
    source: r2:${{ vars.R2_BUCKET }}/staging/${{ github.run_id }}/
    dest: screenshots/${{ inputs.version }}/
    bucket: ${{ vars.R2_BUCKET }}
    endpoint: https://${{ vars.R2_ACCOUNT_ID }}.r2.cloudflarestorage.com
    access_key_id: ${{ secrets.R2_ACCESS_KEY_ID }}
    secret_access_key: ${{ secrets.R2_SECRET_ACCESS_KEY }}
    mode: copy
```

`copy` does not delete extras at the destination. `sync` does. Use
`extra_args: --delete-during` only when you mean it.

Do not use `rclone/` in this repo for this: that action's `copy` operation is a cache, not `rclone copy`.
