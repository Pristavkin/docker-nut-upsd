#!/bin/bash
set -euo pipefail

# Send all output to the systemd journal.
# View logs with: journalctl -t docker-nut-upsd
exec > >(exec logger -t docker-nut-upsd) 2>&1

# Resolve the absolute path of the directory containing this script.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Env file with all configuration/secrets. Override with:
#   ENV_FILE=/path/to/file docker-nut-upsd.sh start
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/.env}"

if [ ! -f "$ENV_FILE" ]; then
    echo "Error: env file not found at $ENV_FILE" >&2
    exit 1
fi

set -a
source "$ENV_FILE"
set +a

: "${CONTAINER_NAME:?CONTAINER_NAME must be set in $ENV_FILE}"
: "${DOCKER_IMAGE:?DOCKER_IMAGE must be set in $ENV_FILE}"
: "${VENDOR_ID:?VENDOR_ID must be set in $ENV_FILE}"
: "${DEVICE_ID:?DEVICE_ID must be set in $ENV_FILE}"
: "${TZ:?TZ must be set in $ENV_FILE}"
: "${ADMIN_PASSWORD:?ADMIN_PASSWORD must be set in $ENV_FILE}"
: "${API_PASSWORD:?API_PASSWORD must be set in $ENV_FILE}"
: "${UPS_DESC:?UPS_DESC must be set in $ENV_FILE}"
HOST_PORT="${HOST_PORT:-3493}"

UPS_DEVICE_PATH=""

# Prevent overlapping start/stop invocations (e.g. a multi-interface USB
# device firing several udev "add" events back to back).
LOCK_FILE="/var/run/docker-nut-upsd.lock"
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    echo "Another docker-nut-upsd.sh invocation is already running, exiting."
    exit 0
fi

# Find the device path based on vendor ID and device ID (HID device)
get_device_path() {
    local device_info
    device_info=$(lsusb | grep -F "ID ${VENDOR_ID}:${DEVICE_ID}" || true)

    if [ -z "$device_info" ]; then
        echo "Error: No UPS device found with vendor ID $VENDOR_ID and device ID $DEVICE_ID." >&2
        exit 1
    fi

    if [ "$(printf '%s\n' "$device_info" | wc -l)" -gt 1 ]; then
        echo "Error: Multiple devices matched vendor ID $VENDOR_ID and device ID $DEVICE_ID; refusing to guess." >&2
        exit 1
    fi

    # e.g. "Bus 002 Device 003: ID 051d:0002 American Power Conversion ..."
    local bus_num dev_num
    bus_num=$(awk '{print $2}' <<<"$device_info")
    dev_num=$(awk '{print $4}' <<<"$device_info" | tr -d ':')

    UPS_DEVICE_PATH="/dev/bus/usb/$bus_num/$dev_num"

    if [ ! -e "$UPS_DEVICE_PATH" ]; then
        echo "Error: Unable to find device at $UPS_DEVICE_PATH." >&2
        exit 1
    fi

    echo "Device found at $UPS_DEVICE_PATH"
}

# Start the Docker container
start_container() {
    get_device_path

    # Check if container is already running
    if docker ps --filter "name=${CONTAINER_NAME}" --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
        echo "Container $CONTAINER_NAME is already running."
        exit 0
    fi

    echo "Starting Docker container for UPS monitoring..."
    docker run -d \
        --name "$CONTAINER_NAME" \
        --hostname "$CONTAINER_NAME" \
        --device "$UPS_DEVICE_PATH:$UPS_DEVICE_PATH" \
        --rm \
        -e TZ="$TZ" \
        -e ADMIN_PASSWORD="$ADMIN_PASSWORD" \
        -e API_PASSWORD="$API_PASSWORD" \
        -e UPS_DESC="$UPS_DESC" \
        -p "0.0.0.0:${HOST_PORT}:3493/tcp" \
        "$DOCKER_IMAGE"
    echo "Docker container started with device $UPS_DEVICE_PATH mounted."
}

# Stop the Docker container
stop_container() {
    if ! docker ps --filter "name=${CONTAINER_NAME}" --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
        echo "Container $CONTAINER_NAME is not running."
        exit 0
    fi

    echo "Stopping Docker container $CONTAINER_NAME..."
    docker stop "$CONTAINER_NAME"
    echo "Docker container stopped."
}

# Handle script arguments: start or stop
case "${1:-}" in
    start)
        start_container
        ;;
    stop)
        stop_container
        ;;
    *)
        echo "Usage: $0 {start|stop}"
        exit 1
        ;;
esac
