#!/bin/bash
set -euo pipefail

# Generic Rclone Script
# Handles various rclone operations with S3/MinIO backend

# Read parameters from environment variables (set by action.yml)
OPERATION="${RCLONE_OPERATION:-copy}"
SOURCE="${RCLONE_SOURCE:-}"
DESTINATION="${RCLONE_DESTINATION:-}"

# Cache-specific parameters (for backward compatibility)
MODE="${CACHE_MODE:-restore-save}"
KEY="${CACHE_KEY:-}"
PATHS="${CACHE_PATHS:-}"
RESTORE_KEYS="${CACHE_RESTORE_KEYS:-}"

# S3/MinIO credentials
ENDPOINT="${RCLONE_ENDPOINT}"
BUCKET="${RCLONE_BUCKET}"
ACCESS_KEY="${RCLONE_ACCESS_KEY}"
SECRET_KEY="${RCLONE_SECRET_KEY}"
REGION="${RCLONE_REGION:-us-east-1}"

# General options
FAIL_ON_MISS="${RCLONE_FAIL_ON_MISS:-false}"
COMPRESSION="${RCLONE_COMPRESSION:-true}"
PROGRESS="${RCLONE_PROGRESS:-true}"
MAX_RETRIES="${RCLONE_MAX_RETRIES:-3}"
RETRY_DELAY="${RCLONE_RETRY_DELAY:-5}"
TIMEOUT="${RCLONE_TIMEOUT:-300}"
PARALLEL_TRANSFERS="${RCLONE_PARALLEL_TRANSFERS:-4}"
BANDWIDTH_LIMIT="${RCLONE_BANDWIDTH_LIMIT:-}"
CHECKERS="${RCLONE_CHECKERS:-8}"
DRY_RUN="${RCLONE_DRY_RUN:-false}"
INCLUDE_FILTERS="${RCLONE_INCLUDE_FILTERS:-}"
EXCLUDE_FILTERS="${RCLONE_EXCLUDE_FILTERS:-}"
CHECKSUM_VERIFY="${RCLONE_CHECKSUM_VERIFY:-true}"

# Input validation functions
validate_url() {
    local url="$1"
    # Basic URL validation - check for http/https protocol and reasonable format
    if [[ ! "$url" =~ ^https?:// ]]; then
        return 1
    fi
    # Extract hostname part (everything between :// and first : or /)
    local hostname="${url#*://}"
    hostname="${hostname%%:*}"
    hostname="${hostname%%/*}"
    
    # Basic hostname validation - must not be empty and not start/end with dot or hyphen
    if [[ -z "$hostname" ]] || [[ "$hostname" =~ ^[.-] ]] || [[ "$hostname" =~ [.-]$ ]] || [[ "$hostname" =~ \.\. ]]; then
        return 1
    fi
    
    return 0
}

validate_bucket_name() {
    local bucket="$1"
    # Basic S3 bucket name validation
    # Must be 3-63 characters, start/end with alphanumeric, contain only lowercase alphanumeric, dots, hyphens
    if [[ ${#bucket} -lt 3 ]] || [[ ${#bucket} -gt 63 ]]; then
        return 1
    fi
    # Must start and end with alphanumeric
    if [[ ! "$bucket" =~ ^[a-z0-9] ]] || [[ ! "$bucket" =~ [a-z0-9]$ ]]; then
        return 1
    fi
    # Must contain only valid characters (no consecutive dots, no dot-hyphen combinations)
    if [[ "$bucket" =~ [^a-z0-9.\-] ]] || [[ "$bucket" =~ \.\. ]] || [[ "$bucket" =~ \.- ]] || [[ "$bucket" =~ -\. ]]; then
        return 1
    fi
    return 0
}

validate_integer() {
    local value="$1"
    if [[ ! "$value" =~ ^[0-9]+$ ]]; then
        return 1
    fi
    return 0
}

validate_bandwidth() {
    local bandwidth="$1"
    if [[ -z "$bandwidth" ]]; then
        return 0  # Empty is valid (no limit)
    fi
    # Validate format like 10M, 1G, 100k, etc.
    if [[ ! "$bandwidth" =~ ^[0-9]+(\.[0-9]+)?[bBkKmMgGtT]?$ ]]; then
        return 1
    fi
    return 0
}

mask_credential() {
    local credential="$1"
    local length=${#credential}
    if [[ $length -le 8 ]]; then
        echo "***"
    else
        echo "${credential:0:4}***${credential: -4}"
    fi
}

# Validate required parameters
if [[ -z "$ENDPOINT" ]] || [[ -z "$BUCKET" ]] || [[ -z "$ACCESS_KEY" ]] || [[ -z "$SECRET_KEY" ]]; then
    log_error "S3/MinIO credentials are required"
    exit 1
fi

# Validate endpoint URL
if ! validate_url "$ENDPOINT"; then
    log_error "Invalid endpoint URL: $ENDPOINT"
    exit 1
fi

# Validate bucket name
if ! validate_bucket_name "$BUCKET"; then
    log_error "Invalid bucket name: $BUCKET"
    exit 1
fi

# Validate numeric parameters
if ! validate_integer "$MAX_RETRIES" || [[ $MAX_RETRIES -lt 1 ]] || [[ $MAX_RETRIES -gt 10 ]]; then
    log_error "Invalid max-retries value: $MAX_RETRIES (must be 1-10)"
    exit 1
fi

if ! validate_integer "$RETRY_DELAY" || [[ $RETRY_DELAY -lt 1 ]] || [[ $RETRY_DELAY -gt 60 ]]; then
    log_error "Invalid retry-delay value: $RETRY_DELAY (must be 1-60 seconds)"
    exit 1
fi

if ! validate_integer "$TIMEOUT" || [[ $TIMEOUT -lt 10 ]] || [[ $TIMEOUT -gt 3600 ]]; then
    log_error "Invalid timeout value: $TIMEOUT (must be 10-3600 seconds)"
    exit 1
fi

if ! validate_integer "$PARALLEL_TRANSFERS" || [[ $PARALLEL_TRANSFERS -lt 1 ]] || [[ $PARALLEL_TRANSFERS -gt 32 ]]; then
    log_error "Invalid parallel-transfers value: $PARALLEL_TRANSFERS (must be 1-32)"
    exit 1
fi

if ! validate_integer "$CHECKERS" || [[ $CHECKERS -lt 1 ]] || [[ $CHECKERS -gt 256 ]]; then
    log_error "Invalid checkers value: $CHECKERS (must be 1-256)"
    exit 1
fi

if ! validate_bandwidth "$BANDWIDTH_LIMIT"; then
    log_error "Invalid bandwidth-limit format: $BANDWIDTH_LIMIT (use format like 10M, 1G, 100k)"
    exit 1
fi

# Validate operation-specific parameters
case "$OPERATION" in
    "copy")
        # For copy (cache) operation, validate cache-specific parameters
        if [[ -z "$KEY" ]]; then
            echo "Error: Cache key is required for copy operation"
            exit 1
        fi
        if [[ -z "$PATHS" ]]; then
            echo "Error: Cache paths are required for copy operation"
            exit 1
        fi
        ;;
    "sync"|"move")
        # For sync/move operations, validate source and destination
        if [[ -z "$SOURCE" ]] || [[ -z "$DESTINATION" ]]; then
            echo "Error: Source and destination are required for $OPERATION operation"
            exit 1
        fi
        ;;
    "delete")
        # For delete operation, validate source
        if [[ -z "$SOURCE" ]]; then
            echo "Error: Source is required for delete operation"
            exit 1
        fi
        ;;
    "size")
        # For size operation, validate source
        if [[ -z "$SOURCE" ]]; then
            echo "Error: Source is required for size operation"
            exit 1
        fi
        ;;
    *)
        echo "Error: Unsupported operation: $OPERATION"
        echo "Supported operations: copy, sync, move, delete, size"
        exit 1
        ;;
esac

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Structured logging with JSON output
log_json() {
    local level="$1"
    local message="$2"
    local extra_fields="$3"
    
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local json_log="{\"timestamp\":\"$timestamp\",\"level\":\"$level\",\"message\":\"$message\""
    
    if [[ -n "$extra_fields" ]]; then
        json_log="$json_log,$extra_fields"
    fi
    
    json_log="$json_log}"
    echo "$json_log"
}

# Transfer statistics collection
collect_transfer_stats() {
    local operation="$1"
    local start_time="$2"
    local end_time="$3"
    local bytes_transferred="$4"
    local files_transferred="${5:-0}"
    local errors="${6:-0}"
    
    local duration=$((end_time - start_time))
    local transfer_rate=0
    
    if [[ $duration -gt 0 && $bytes_transferred -gt 0 ]]; then
        transfer_rate=$((bytes_transferred / duration))
    fi
    
    local stats_json="\"operation\":\"$operation\",\"duration_seconds\":$duration,\"bytes_transferred\":$bytes_transferred,\"files_transferred\":$files_transferred,\"errors\":$errors,\"transfer_rate_bytes_per_second\":$transfer_rate"
    
    log_json "INFO" "Transfer completed" "$stats_json"
    
    # Export for GitHub Actions
    {
        echo "transfer-duration=$duration"
        echo "transfer-rate=$transfer_rate"
        echo "files-transferred=$files_transferred"
        echo "errors=$errors"
    } >> "$GITHUB_OUTPUT"
}

# Display operation summary
display_operation_summary() {
    local operation="$1"
    local result="$2"
    local bytes_transferred="$3"
    local files_transferred="$4"
    local duration="$5"
    local transfer_rate="$6"
    
    echo
    echo "┌─────────────────────────────────────────────────────────────────────────┐"
    echo "│                             OPERATION SUMMARY                           │"
    echo "├─────────────────────────────────────────────────────────────────────────┤"
    printf "│ Operation:        %-50s │\n" "$operation"
    printf "│ Result:           %-50s │\n" "$result"
    printf "│ Files:            %-50s │\n" "$files_transferred"
    printf "│ Data transferred: %-50s │\n" "$(format_bytes "$bytes_transferred")"
    printf "│ Duration:         %-50s │\n" "$(format_duration "$duration")"
    printf "│ Transfer rate:    %-50s │\n" "$(format_bytes_per_second "$transfer_rate")"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "│                                                                         │"
        echo "│ ⚠️  DRY RUN MODE - No actual changes were made                        │"
    fi
    
    echo "└─────────────────────────────────────────────────────────────────────────┘"
    echo
}

# Format bytes for human-readable display
format_bytes() {
    local bytes="$1"
    if [[ $bytes -lt 1024 ]]; then
        echo "${bytes}B"
    elif [[ $bytes -lt 1048576 ]]; then
        echo "$((bytes / 1024))KB"
    elif [[ $bytes -lt 1073741824 ]]; then
        echo "$((bytes / 1048576))MB"
    else
        echo "$((bytes / 1073741824))GB"
    fi
}

# Format duration for human-readable display
format_duration() {
    local seconds="$1"
    if [[ $seconds -lt 60 ]]; then
        echo "${seconds}s"
    elif [[ $seconds -lt 3600 ]]; then
        echo "$((seconds / 60))m $((seconds % 60))s"
    else
        echo "$((seconds / 3600))h $((seconds % 3600 / 60))m $((seconds % 60))s"
    fi
}

# Format transfer rate for human-readable display
format_bytes_per_second() {
    local bytes_per_second="$1"
    if [[ $bytes_per_second -eq 0 ]]; then
        echo "0B/s"
    else
        echo "$(format_bytes "$bytes_per_second")/s"
    fi
}

# Retry helper function with exponential backoff
retry_with_backoff() {
    local max_attempts="$1"
    local delay="$2"
    local command=("${@:3}")
    local attempt=1
    
    while (( attempt <= max_attempts )); do
        log_info "Attempt $attempt of $max_attempts: ${command[*]}"
        
        if "${command[@]}"; then
            log_success "Command succeeded on attempt $attempt"
            return 0
        else
            local exit_code=$?
            if (( attempt < max_attempts )); then
                local sleep_time=$((delay * (2 ** (attempt - 1))))
                log_warning "Command failed (exit code: $exit_code), retrying in ${sleep_time}s..."
                sleep "$sleep_time"
            else
                log_error "Command failed after $max_attempts attempts"
                return $exit_code
            fi
        fi
        
        ((attempt++))
    done
}

# Execute rclone command with retry logic
execute_rclone_with_retry() {
    local rclone_args=("$@")
    
    # Add timeout if specified
    if [[ "$TIMEOUT" -gt 0 ]]; then
        rclone_args=("--timeout" "${TIMEOUT}s" "${rclone_args[@]}")
    fi
    
    retry_with_backoff "$MAX_RETRIES" "$RETRY_DELAY" rclone "${rclone_args[@]}"
}

# Install rclone if not available
install_rclone() {
    if ! command -v rclone &> /dev/null; then
        log_info "Installing rclone..."
        curl -s https://rclone.org/install.sh | sudo bash
    fi
    log_success "rclone version: $(rclone version | head -1)"
}

# Configure rclone for S3/MinIO
configure_rclone() {
    log_info "Configuring rclone for S3/MinIO..."
    log_info "Endpoint: $ENDPOINT"
    log_info "Bucket: $BUCKET"
    log_info "Region: $REGION"
    log_info "Access Key: $(mask_credential "$ACCESS_KEY")"
    log_info "Secret Key: $(mask_credential "$SECRET_KEY")"
    
    mkdir -p ~/.config/rclone
    
    cat > ~/.config/rclone/rclone.conf << EOF
[remote]
type = s3
provider = Other
endpoint = ${ENDPOINT}
access_key_id = ${ACCESS_KEY}
secret_access_key = ${SECRET_KEY}
region = ${REGION}
acl = private
EOF
    
    # Set restrictive permissions on config file
    chmod 600 ~/.config/rclone/rclone.conf
    
    log_success "rclone configured with masked credentials"
}

# Build rclone command options
build_rclone_options() {
    local options=""
    
    if [[ "$PROGRESS" == "true" ]]; then
        options="$options --progress"
    fi
    
    # Dry run mode
    if [[ "$DRY_RUN" == "true" ]]; then
        options="$options --dry-run"
    fi
    
    # Performance options
    options="$options --transfers $PARALLEL_TRANSFERS"
    options="$options --checkers $CHECKERS"
    
    # Bandwidth limiting
    if [[ -n "$BANDWIDTH_LIMIT" ]]; then
        options="$options --bwlimit $BANDWIDTH_LIMIT"
    fi
    
    # Include filters
    if [[ -n "$INCLUDE_FILTERS" ]]; then
        # Convert filters to array
        IFS=' ' read -ra include_filters_array <<< "$(echo "$INCLUDE_FILTERS" | tr '\n' ' ')"
        for filter in "${include_filters_array[@]}"; do
            options="$options --include '$filter'"
        done
    fi
    
    # Exclude filters
    if [[ -n "$EXCLUDE_FILTERS" ]]; then
        # Convert filters to array
        IFS=' ' read -ra exclude_filters_array <<< "$(echo "$EXCLUDE_FILTERS" | tr '\n' ' ')"
        for filter in "${exclude_filters_array[@]}"; do
            options="$options --exclude '$filter'"
        done
    fi
    
    # Checksum verification
    if [[ "$CHECKSUM_VERIFY" == "true" ]]; then
        options="$options --checksum"
    fi
    
    # Additional performance optimizations
    options="$options --multi-thread-streams 4"
    options="$options --use-list-r"
    options="$options --fast-list"
    
    echo "$options"
}

# Execute generic rclone operations
execute_sync_operation() {
    local source="$1"
    local destination="$2"
    local operation="$3"
    
    local dry_run_msg=""
    if [[ "$DRY_RUN" == "true" ]]; then
        dry_run_msg=" (DRY RUN)"
    fi
    
    log_info "Executing rclone $operation from $source to $destination$dry_run_msg"
    log_json "INFO" "Starting operation" "\"operation\":\"$operation\",\"source\":\"$source\",\"destination\":\"$destination\",\"dry_run\":$DRY_RUN"
    
    local options
    options=$(build_rclone_options)
    local bytes_transferred=0
    local files_transferred=0
    local errors=0
    local start_time
    start_time=$(date +%s)
    
    case "$operation" in
        "sync")
            if execute_rclone_with_retry sync "$source" "$destination" $options --stats 1s --stats-one-line 2>&1 | tee /tmp/rclone_output.log; then
                log_success "Sync completed successfully"
                echo "operation-result=success" >> "$GITHUB_OUTPUT"
            else
                log_error "Sync failed"
                echo "operation-result=failed" >> "$GITHUB_OUTPUT"
                errors=1
            fi
            ;;
        "move")
            if execute_rclone_with_retry move "$source" "$destination" $options --stats 1s --stats-one-line 2>&1 | tee /tmp/rclone_output.log; then
                log_success "Move completed successfully"
                echo "operation-result=success" >> "$GITHUB_OUTPUT"
            else
                log_error "Move failed"
                echo "operation-result=failed" >> "$GITHUB_OUTPUT"
                errors=1
            fi
            ;;
    esac
    
    local end_time=$(date +%s)
    
    # Parse rclone output for statistics
    if [[ -f /tmp/rclone_output.log ]]; then
        # Extract bytes transferred from rclone output
        local bytes_line=$(grep -E "Transferred:" /tmp/rclone_output.log | tail -1)
        if [[ -n "$bytes_line" ]]; then
            bytes_transferred=$(echo "$bytes_line" | grep -oE '[0-9]+(\.[0-9]+)?\s*[KMGT]?B' | head -1 | sed 's/[^0-9.]//g')
            # Convert to bytes if needed (simplified for now)
            if [[ -z "$bytes_transferred" ]]; then
                bytes_transferred=0
            fi
        fi
        
        # Extract files transferred count
        local files_line=$(grep -E "Transferred:" /tmp/rclone_output.log | tail -1)
        if [[ -n "$files_line" ]]; then
            files_transferred=$(echo "$files_line" | grep -oE '[0-9]+\s*/' | head -1 | sed 's/[^0-9]//g')
            if [[ -z "$files_transferred" ]]; then
                files_transferred=0
            fi
        fi
        
        rm -f /tmp/rclone_output.log
    fi
    
    collect_transfer_stats "$operation" "$start_time" "$end_time" "$bytes_transferred" "$files_transferred" "$errors"
    echo "bytes-transferred=$bytes_transferred" >> $GITHUB_OUTPUT
    
    if [[ $errors -gt 0 ]]; then
        return 1
    fi
}

# Execute delete operation
execute_delete_operation() {
    local target="$1"
    
    log_info "Executing rclone delete on $target"
    
    local options
    options=$(build_rclone_options)
    
    if execute_rclone_with_retry delete "$target" $options; then
        log_success "Delete completed successfully"
        echo "operation-result=success" >> "$GITHUB_OUTPUT"
    else
        log_error "Delete failed"
        echo "operation-result=failed" >> "$GITHUB_OUTPUT"
        return 1
    fi
    
    echo "bytes-transferred=0" >> $GITHUB_OUTPUT
}

# Execute size operation
execute_size_operation() {
    local target="$1"
    
    log_info "Getting size of $target"
    
    local size_output
    if size_output=$(execute_rclone_with_retry size "$target" --json 2>/dev/null); then
        local bytes=$(echo "$size_output" | grep -o '"bytes":[0-9]*' | cut -d':' -f2)
        local count=$(echo "$size_output" | grep -o '"count":[0-9]*' | cut -d':' -f2)
        
        log_success "Size: $bytes bytes ($count files)"
        echo "operation-result=success" >> "$GITHUB_OUTPUT"
        echo "bytes-transferred=$bytes" >> $GITHUB_OUTPUT
    else
        log_error "Failed to get size"
        echo "operation-result=failed" >> "$GITHUB_OUTPUT"
        echo "bytes-transferred=0" >> $GITHUB_OUTPUT
        return 1
    fi
}

# Cache-specific functions (from original script)
check_cache() {
    local cache_hit="false"
    local cache_key=""
    
    log_info "Checking for cache..."
    
    # Try exact key first
    local cache_path="remote:${BUCKET}/${KEY}"
    
    if execute_rclone_with_retry lsf "$cache_path" &>/dev/null; then
        log_success "Found exact cache: $KEY"
        cache_hit="true"
        cache_key="$KEY"
    else
        log_warning "Exact cache not found: $KEY"
        
        # Try restore keys
        if [[ -n "$RESTORE_KEYS" ]]; then
            # Convert restore keys to array
            IFS=' ' read -ra restore_keys_array <<< "$(echo "$RESTORE_KEYS" | tr '\n' ' ')"
            
            for restore_key in "${restore_keys_array[@]}"; do
                log_info "Trying restore key: $restore_key"
                
                # List all keys matching the prefix
                local matches=$(execute_rclone_with_retry lsf "remote:${BUCKET}/" --include "${restore_key}*" 2>/dev/null | sort -r | head -1)
                
                if [[ -n "$matches" ]]; then
                    cache_key="${matches%/}"
                    log_success "Found cache with restore key: $cache_key"
                    cache_hit="true"
                    break
                fi
            done
        fi
        
        if [[ "$cache_hit" == "false" ]]; then
            log_warning "No cache found"
            
            if [[ "$FAIL_ON_MISS" == "true" ]]; then
                log_error "Cache miss and fail-on-miss is true"
                exit 1
            fi
        fi
    fi
    
    # Output for GitHub Actions
    echo "cache-hit=$cache_hit" >> $GITHUB_OUTPUT
    echo "cache-key=$cache_key" >> $GITHUB_OUTPUT
}

# Restore cache from S3/MinIO
restore_cache() {
    local cache_key="${1}"
    
    if [[ -z "$cache_key" ]]; then
        log_warning "No cache to restore"
        return 0
    fi
    
    log_info "Restoring cache from key: $cache_key"
    
    local cache_path="remote:${BUCKET}/${cache_key}"
    local temp_dir=$(mktemp -d)
    
    # Convert paths to array
    IFS=' ' read -ra paths_array <<< "$(echo "$PATHS" | tr '\n' ' ')"
    
    if [[ "$COMPRESSION" == "true" ]]; then
        log_info "Downloading compressed cache..."
        local options
    options=$(build_rclone_options)
        if ! execute_rclone_with_retry copy "$cache_path/cache.tar.gz" "$temp_dir" $options; then
            log_error "Failed to download cache"
            rm -rf "$temp_dir"
            return 1
        fi
        
        log_info "Extracting cache..."
        if ! tar -xzf "$temp_dir/cache.tar.gz" -C /; then
            log_error "Failed to extract cache"
            rm -rf "$temp_dir"
            return 1
        fi
    else
        log_info "Downloading cache directories..."
        local options
    options=$(build_rclone_options)
        
        for path in "${paths_array[@]}"; do
            log_info "Restoring: $path"
            local parent_dir=$(dirname "$path")
            mkdir -p "$parent_dir"
            
            if ! execute_rclone_with_retry copy "$cache_path/$(basename $path)" "$parent_dir/$(basename $path)" $options; then
                log_warning "Failed to restore: $path"
            fi
        done
    fi
    
    # Cleanup
    rm -rf "$temp_dir"
    
    log_success "Cache restored successfully"
}

# Save cache to S3/MinIO
save_cache() {
    log_info "Saving cache with key: $KEY"
    
    local cache_path="remote:${BUCKET}/${KEY}"
    
    # Check if cache already exists
    if execute_rclone_with_retry lsf "$cache_path" &>/dev/null; then
        log_info "Cache already exists for key: $KEY"
        return 0
    fi
    
    # Convert paths to array
    IFS=' ' read -ra paths_array <<< "$(echo "$PATHS" | tr '\n' ' ')"
    
    # Create temp directory for compression
    local temp_dir=$(mktemp -d)
    local bytes_transferred=0
    
    if [[ "$COMPRESSION" == "true" ]]; then
        log_info "Creating compressed cache..."
        
        # Build tar arguments
        local tar_args=""
        local found_paths=false
        
        for path in "${paths_array[@]}"; do
            if [[ -e "$path" ]]; then
                tar_args="$tar_args $path"
                found_paths=true
            else
                log_warning "Path not found: $path"
            fi
        done
        
        if [[ "$found_paths" == "false" ]]; then
            log_error "No paths found to cache"
            rm -rf "$temp_dir"
            return 1
        fi
        
        log_info "Compressing paths: $tar_args"
        if ! tar -czf "$temp_dir/cache.tar.gz" $tar_args; then
            log_error "Failed to create cache archive"
            rm -rf "$temp_dir"
            return 1
        fi
        
        log_info "Uploading compressed cache..."
        local options
    options=$(build_rclone_options)
        if ! execute_rclone_with_retry copy "$temp_dir/cache.tar.gz" "$cache_path/" $options; then
            log_error "Failed to upload cache"
            rm -rf "$temp_dir"
            return 1
        fi
        
        # Get size of uploaded file
        bytes_transferred=$(stat -c%s "$temp_dir/cache.tar.gz" 2>/dev/null || echo "0")
    else
        log_info "Uploading cache directories..."
        local options
    options=$(build_rclone_options)
        
        local uploaded=false
        for path in "${paths_array[@]}"; do
            if [[ -e "$path" ]]; then
                log_info "Saving: $path"
                if execute_rclone_with_retry copy "$path" "$cache_path/$(basename $path)" $options; then
                    uploaded=true
                else
                    log_warning "Failed to save: $path"
                fi
            else
                log_warning "Path not found: $path"
            fi
        done
        
        if [[ "$uploaded" == "false" ]]; then
            log_error "No paths were uploaded"
            rm -rf "$temp_dir"
            return 1
        fi
    fi
    
    # Cleanup
    rm -rf "$temp_dir"
    
    log_success "Cache saved successfully"
    echo "bytes-transferred=$bytes_transferred" >> $GITHUB_OUTPUT
}

# Execute cache operations
execute_cache_operation() {
    case "$MODE" in
        "restore")
            check_cache
            if [[ -f "$GITHUB_OUTPUT" ]]; then
                source "$GITHUB_OUTPUT"
                if [[ "$cache_hit" == "true" ]]; then
                    restore_cache "$cache_key"
                fi
            fi
            ;;
            
        "save")
            save_cache
            ;;
            
        "restore-save")
            # First try to restore
            check_cache
            if [[ -f "$GITHUB_OUTPUT" ]]; then
                source "$GITHUB_OUTPUT"
                if [[ "$cache_hit" == "true" ]]; then
                    restore_cache "$cache_key"
                else
                    # No cache found, we'll save after the job
                    log_info "Will save cache after job completion"
                fi
            fi
            ;;
            
        *)
            log_error "Invalid cache mode: $MODE"
            exit 1
            ;;
    esac
    
    echo "operation-result=success" >> "$GITHUB_OUTPUT"
}

# Main execution
main() {
    log_info "Starting rclone $OPERATION operation"
    
    # Install and configure rclone
    install_rclone
    configure_rclone
    
    # Initialize default outputs
    echo "operation-result=pending" >> $GITHUB_OUTPUT
    echo "bytes-transferred=0" >> $GITHUB_OUTPUT
    
    # Execute based on operation
    case "$OPERATION" in
        "copy")
            execute_cache_operation
            ;;
        "sync")
            execute_sync_operation "$SOURCE" "$DESTINATION" "sync"
            ;;
        "move")
            execute_sync_operation "$SOURCE" "$DESTINATION" "move"
            ;;
        "delete")
            execute_delete_operation "$SOURCE"
            ;;
        "size")
            execute_size_operation "$SOURCE"
            ;;
        *)
            log_error "Unsupported operation: $OPERATION"
            exit 1
            ;;
    esac
    
    # Display operation summary
    local result="success"
    local bytes_transferred=0
    local files_transferred=0
    local duration=0
    local transfer_rate=0
    
    # Read values from GitHub outputs if available
    if [[ -f "$GITHUB_OUTPUT" ]]; then
        bytes_transferred=$(grep "bytes-transferred=" "$GITHUB_OUTPUT" | cut -d'=' -f2 | tail -1)
        files_transferred=$(grep "files-transferred=" "$GITHUB_OUTPUT" | cut -d'=' -f2 | tail -1)
        duration=$(grep "transfer-duration=" "$GITHUB_OUTPUT" | cut -d'=' -f2 | tail -1)
        transfer_rate=$(grep "transfer-rate=" "$GITHUB_OUTPUT" | cut -d'=' -f2 | tail -1)
        result=$(grep "operation-result=" "$GITHUB_OUTPUT" | cut -d'=' -f2 | tail -1)
    fi
    
    display_operation_summary "$OPERATION" "$result" "${bytes_transferred:-0}" "${files_transferred:-0}" "${duration:-0}" "${transfer_rate:-0}"
    
    log_success "Operation completed successfully"
}

# Run main function
main