# ============================
# Multi-Arch Flutter Build Makefile
# For Apple Silicon + Podman
# ============================

SERVICE := flutter-build
IMAGE := flutter-linux

# ----------------------------
# Podman Machine Helpers
# ----------------------------

podman-start:
	@echo "🐧 Ensuring Podman machine is running..."
	@podman machine start podman-machine-default 2>/dev/null || true
	@podman info 2>/dev/null | grep -q "host:" || (echo "❌ Podman machine not running. Run: podman machine start" && exit 1)

# ----------------------------
# Docker Image Builds
# ----------------------------

image-arm: podman-start
	@echo "🐳 Building ARM64 Docker image..."
	podman build --platform linux/arm64 -t $(IMAGE):arm64 .

image-amd: podman-start
	@echo "🐳 Building x86-64 Docker image..."
	podman build --platform linux/amd64 -t $(IMAGE):amd64 .

# ----------------------------
# Flutter Builds
# ----------------------------

build-arm: podman-start
	@echo "🚀 Building Flutter Linux ARM64..."
	TARGETARCH=arm64 podman compose run --rm $(SERVICE) bash -c "flutter pub get && ./flutter_with_commit.sh build linux --release"

build-amd: podman-start
	@echo "🚀 Building Flutter Linux x86_64..."
	TARGETARCH=amd64 podman compose run --rm $(SERVICE) bash -c "flutter pub get && ./flutter_with_commit.sh build linux --release"

dual-build: build-arm build-amd
	@echo "🎉 Dual build complete!"

# ----------------------------
# Shells
# ----------------------------

shell-arm: podman-start
	podman compose run --rm $(SERVICE)

shell-amd: podman-start
	podman compose run --rm $(SERVICE)

# ----------------------------
# Clean All Caches
# ----------------------------

clean:
	@echo "🧹 Cleaning all containers, volumes, and caches..."
	podman compose down -v || true
	podman volume rm -f reaprime_flutter_pub_cache_arm64 reaprime_flutter_sdk_cache_arm64 || true
	podman image prune -f
