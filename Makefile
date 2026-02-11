# ============================
# Multi-Arch Flutter Build Makefile
# For M2 Mac + Colima
# ============================

SERVICE := flutter-build
IMAGE := flutter-linux

ARM_PROFILE := flutter-arm
AMD_PROFILE := flutter-amd

# ----------------------------
# Colima Profile Helpers
# ----------------------------

colima-stop:
	@echo "🛑 Stopping Colima..."
	@colima stop || true
	@sleep 2

colima-arm: colima-stop
	@echo "🐧 Starting Colima (ARM64)..."
	@colima start --profile flutter-arm --arch aarch64 --vm-type=qemu --cpu 4 --memory 8
	@docker info | grep Architecture

colima-amd: colima-stop
	@echo "💻 Starting Colima (x86_64)..."
	@colima start --profile flutter-amd --arch x86_64 --vm-type=qemu --cpu 4 --memory 8
	@docker info | grep Architecture

# Convenience shortcuts
arm: colima-arm
amd: colima-amd

# ----------------------------
# Docker Image Builds
# ----------------------------

image-arm: arm
	@echo "🐳 Building ARM64 Docker image..."
	docker buildx build --platform linux/arm64 -t $(IMAGE):arm64 --load .

image-amd: amd
	@echo "🐳 Building x86-64 Docker image..."
	docker buildx build --platform linux/amd64 -t $(IMAGE):amd64 --load .

# ----------------------------
# Flutter Builds
# ----------------------------

build-arm: arm
	@echo "🚀 Building Flutter Linux ARM64..."
	TARGETARCH=arm64 docker compose run --rm $(SERVICE) bash -c "flutter pub get && ./flutter_with_commit.sh build linux --release"

build-amd: amd
	@echo "🚀 Building Flutter Linux x86_64..."
	TARGETARCH=amd64 docker compose run --rm $(SERVICE) bash -c "flutter pub get && ./flutter_with_commit.sh build linux --release"

dual-build: build-arm build-amd
	@echo "🎉 Dual build complete!"

# ----------------------------
# Shells
# ----------------------------

shell-arm: arm
	docker compose run --rm $(SERVICE)

shell-amd: amd
	docker compose run --rm $(SERVICE)

# ----------------------------
# Clean All Caches
# ----------------------------

clean:
	@echo "🧹 Cleaning all containers, volumes, and caches..."
	docker compose down -v || true
	docker volume rm -f flutter_pub_cache_amd64 flutter_pub_cache_arm64 \
	                  flutter_sdk_cache_amd64 flutter_sdk_cache_arm64 || true
	docker image prune -f
