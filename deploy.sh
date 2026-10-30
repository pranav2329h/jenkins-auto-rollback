#!/usr/bin/env bash

set -Eeuo pipefail

APP_NAME="auto-rollback-app"
APP_PORT="5000"
STATE_DIR="/opt/auto-rollback"
PREVIOUS_IMAGE_FILE="${STATE_DIR}/previous-image"

NEW_IMAGE="${1:-}"

if [[ -z "$NEW_IMAGE" ]]; then
    echo "ERROR: Image name is required."
    echo "Usage: ./deploy.sh <docker-image:tag>"
    exit 1
fi

echo "======================================"
echo "Starting deployment"
echo "Candidate image: ${NEW_IMAGE}"
echo "======================================"

# Get the image currently used by the application container.
OLD_IMAGE=""

if sudo docker container inspect "${APP_NAME}" >/dev/null 2>&1; then
    OLD_IMAGE=$(sudo docker inspect \
        --format='{{.Config.Image}}' "${APP_NAME}")

    echo "Previous image: ${OLD_IMAGE}"
else
    echo "No previous application container found."
fi

# Pull the candidate image from Docker Hub.
echo "Pulling candidate image..."

if ! sudo docker pull "${NEW_IMAGE}"; then
    echo "ERROR: Unable to pull candidate image."
    exit 1
fi

# Stop and remove the current application container.
if sudo docker container inspect "${APP_NAME}" >/dev/null 2>&1; then
    echo "Stopping previous application..."

    sudo docker stop "${APP_NAME}" || true
    sudo docker rm "${APP_NAME}" || true
fi

# Start the candidate version.
echo "Starting candidate application..."

if ! sudo docker run -d \
    --name "${APP_NAME}" \
    --restart unless-stopped \
    -p "${APP_PORT}:5000" \
    "${NEW_IMAGE}"; then

    echo "ERROR: Candidate container failed to start."

    if [[ -n "${OLD_IMAGE}" ]]; then
        echo "Restoring previous image: ${OLD_IMAGE}"

        sudo docker rm -f "${APP_NAME}" >/dev/null 2>&1 || true

        sudo docker run -d \
            --name "${APP_NAME}" \
            --restart unless-stopped \
            -p "${APP_PORT}:5000" \
            "${OLD_IMAGE}"
    fi

    exit 1
fi

# Check application health.
echo "Checking candidate health..."

HEALTHY="false"

for attempt in $(seq 1 15); do
    if curl -fsS \
        "http://127.0.0.1:${APP_PORT}/health" >/dev/null; then

        HEALTHY="true"
        echo "Health check passed on attempt ${attempt}."
        break
    fi

    echo "Attempt ${attempt}/15: application is not healthy yet."
    sleep 2
done

# Keep candidate if healthy.
if [[ "${HEALTHY}" == "true" ]]; then
    if [[ -n "${OLD_IMAGE}" ]]; then
        echo "${OLD_IMAGE}" > "${PREVIOUS_IMAGE_FILE}"
    fi

    echo "======================================"
    echo "DEPLOYMENT SUCCESS"
    echo "Running image: ${NEW_IMAGE}"
    echo "======================================"

    sudo docker ps --filter "name=${APP_NAME}"

    exit 0
fi

# Candidate failed. Remove it and restore the old image.
echo "======================================"
echo "HEALTH CHECK FAILED"
echo "Starting rollback..."
echo "======================================"

sudo docker logs "${APP_NAME}" || true
sudo docker rm -f "${APP_NAME}" >/dev/null 2>&1 || true

if [[ -z "${OLD_IMAGE}" ]]; then
    echo "No previous image exists. Cannot perform rollback."
    exit 1
fi

echo "Restoring previous image: ${OLD_IMAGE}"

sudo docker run -d \
    --name "${APP_NAME}" \
    --restart unless-stopped \
    -p "${APP_PORT}:5000" \
    "${OLD_IMAGE}"

# Verify rollback health.
ROLLBACK_HEALTHY="false"

for attempt in $(seq 1 15); do
    if curl -fsS \
        "http://127.0.0.1:${APP_PORT}/health" >/dev/null; then

        ROLLBACK_HEALTHY="true"
        echo "Rollback health check passed."
        break
    fi

    echo "Rollback attempt ${attempt}/15: waiting..."
    sleep 2
done

if [[ "${ROLLBACK_HEALTHY}" == "true" ]]; then
    echo "ROLLBACK SUCCESS: Previous version restored."
else
    echo "CRITICAL: Rollback health check failed."
    sudo docker logs "${APP_NAME}" || true
fi

# Deployment failed even if rollback succeeded.
exit 1
