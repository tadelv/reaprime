# 🐧 Makefile for building Flutter Linux ARM64 app in Colima
# Usage:
#   make linux-build        -> Build release bundle
#   make linux-shell        -> Drop into interactive container
#   make linux-clean        -> Clean build cache
#   make colima-start       -> Start Colima if not already running

COLIMA_NAME ?= default
SERVICE := flutter-build

# Default target
linux-build: colima-start
	@echo "🚀 Building Flutter Linux ARM64 app..."
	docker compose run --rm $(SERVICE) bash -c "flutter pub get && flutter build linux --release"

linux-shell: colima-start
	@echo "💻 Opening shell in Flutter build container..."
	docker compose run --rm $(SERVICE)

linux-clean:
	@echo "🧹 Cleaning build and cache volumes..."
	docker compose down -v
	docker volume rm -f $$(docker volume ls -q | grep flutter_build_cache || true)

colima-start:
	@echo "🧩 Ensuring Colima is running (ARM64 mode)..."
	@if ! colima status | grep -q 'running'; then \
		echo "Starting Colima for ARM64..."; \
		colima start --arch aarch64 --vm-type=vz --cpu 4 --memory 8; \
	else \
		echo "Colima already running ✅"; \
	fi
