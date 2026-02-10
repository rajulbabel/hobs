#!/bin/bash
set -e

echo "=== Starting Pi Simulator ==="
echo ""
echo "This simulates a Raspberry Pi with Docker running inside it."
echo "Immich will be accessible at http://localhost:8080"
echo ""

# Start the Pi simulator container
docker compose up -d

echo ""
echo "Waiting for Docker-in-Docker to be ready..."
sleep 5

# Shell into the Pi and start Immich
echo "Starting Immich inside the Pi simulator..."
docker compose exec pi sh -c "
  cd /home/deploy && \
  docker compose pull && \
  docker compose up -d
"

echo ""
echo "=== Pi Simulator is running ==="
echo "  Immich UI:  http://localhost:8080"
echo ""
echo "To shell into the Pi:  docker compose exec pi sh"
echo "To view Pi logs:       docker compose exec pi sh -c 'cd /home/deploy && docker compose logs -f'"
echo "To stop everything:    docker compose down"
