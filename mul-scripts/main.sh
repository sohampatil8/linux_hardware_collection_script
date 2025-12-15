#!/usr/bin/env bash
# Multi-host Linux Inventory Scanner with Parallel Execution + Logging

set -uo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
HOSTS_FILE="$SCRIPT_DIR/hosts.txt"
REMOTE_SCRIPT="/tmp/linux_inventory.sh"
LOCAL_INVENTORY="$SCRIPT_DIR/hw_inventory.sh"
MERGED_CSV="$SCRIPT_DIR/linux_inventory_merged.csv"
LOG_DIR="$SCRIPT_DIR/logs"

mkdir -p "$LOG_DIR"

# Host scan timeout (SSH + Script Execution)
TIMEOUT_SECONDS=60

if [ ! -f "$HOSTS_FILE" ]; then
    echo "ERROR: hosts.txt file not found"
    exit 1
fi

if [ ! -f "$LOCAL_INVENTORY" ]; then
    echo "ERROR: inventory.sh file not found"
    exit 1
fi

echo "Starting parallel scan of all Linux machines..."
echo "Logs stored in: $LOG_DIR"
echo "--------------------------------------------------"

# Clear merged file
echo "" > "$MERGED_CSV"
HEADER_WRITTEN=0

scan_host() {
    ENTRY="$1"
    USER=$(echo "$ENTRY" | cut -d@ -f1)
    HOST=$(echo "$ENTRY" | cut -d@ -f2)
    LOGFILE="$LOG_DIR/${HOST}.log"

    {
        echo "=== Scan Started for $USER@$HOST ==="
        date

        # Check SSH connection
        timeout $TIMEOUT_SECONDS ssh -o BatchMode=yes -o ConnectTimeout=10 "$USER@$HOST" "echo ok" 2>/dev/null
        if [ $? -ne 0 ]; then
            echo "[ERROR] SSH connection failed for $HOST"
            echo "STATUS: FAILED" >> "$LOGFILE"
            exit 1
        fi

        echo "SSH connection successful."

        # Upload inventory script
        scp "$LOCAL_INVENTORY" "$USER@$HOST:$REMOTE_SCRIPT" >/dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo "[ERROR] SCP upload failed for $HOST"
            exit 1
        fi

        echo "Inventory script uploaded."

        # Execute remote script with timeout
        timeout $TIMEOUT_SECONDS ssh "$USER@$HOST" "bash $REMOTE_SCRIPT" >/dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo "[ERROR] Script execution failed or timed out on $HOST"
            exit 1
        fi

        echo "Remote scan completed."

        # Download generated CSV
        REMOTE_CSV="/tmp/linux_inventory.csv"
        LOCAL_CSV="$SCRIPT_DIR/linux_${HOST}.csv"
        scp "$USER@$HOST:$REMOTE_CSV" "$LOCAL_CSV" >/dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo "[ERROR] Failed to download CSV from $HOST"
            exit 1
        fi

        echo "CSV downloaded to $LOCAL_CSV"

        # Merge into master CSV
        if [ $HEADER_WRITTEN -eq 0 ]; then
            head -n 1 "$LOCAL_CSV" >> "$MERGED_CSV"
            HEADER_WRITTEN=1
        fi
        tail -n 1 "$LOCAL_CSV" >> "$MERGED_CSV"

        echo "Merged into master report."

        echo "STATUS: SUCCESS"
        date
        echo "=== Scan Completed ==="

    } > "$LOGFILE" 2>&1
}

# Export function for parallel use
export -f scan_host
export SCRIPT_DIR MERGED_CSV HEADER_WRITTEN LOCAL_INVENTORY REMOTE_SCRIPT LOG_DIR

# Run in parallel (one background job per host)
for HOSTENTRY in $(cat "$HOSTS_FILE"); do
    scan_host "$HOSTENTRY" &
done

wait

echo "--------------------------------------------------"
echo "All scans completed!"
echo "Final merged CSV: $MERGED_CSV"
echo "Check logs folder for per-host debugging."
