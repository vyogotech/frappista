# Configuration
REGISTRY=docker.io
REPO=vyogo
IMAGE_NAME=$(REGISTRY)/$(REPO)/frappe:s2i-base
VERSION?=latest
ERP_IMAGE_NAME=$(REGISTRY)/$(REPO)/erpnext:sne-latest

# Default target
.PHONY: all
all: help

# Show help information
.PHONY: help
help:
	@echo "Available targets:"
	@echo " build - Build image for current architecture"
	@echo " build-amd64 - Build image for AMD64 architecture"
	@echo " build-arm64 - Build image for ARM64 architecture"
	@echo " push - Push current image to registry"
	@echo " push-amd64 - Push AMD64 image to registry"
	@echo " push-arm64 - Push ARM64 image to registry"
	@echo " push-manifest - Create and push a multi-arch manifest"
	@echo " erpnext - Build ERPNext image"
	@echo " erpnext-amd64 - Build ERPNext for AMD64"
	@echo " erpnext-arm64 - Build ERPNext for ARM64"
	@echo " clean - Remove all images"

# Build for current architecture
.PHONY: build
build:
	podman build -t $(IMAGE_NAME) .

# Build for AMD64
.PHONY: build-amd64
build-amd64:
	podman build --arch=amd64 -t $(IMAGE_NAME)-amd64 .

# Build for ARM64
.PHONY: build-arm64
build-arm64:
	podman build --arch=arm64 -t $(IMAGE_NAME)-arm64 .

# Push images
.PHONY: push push-amd64 push-arm64
push:
	podman push $(IMAGE_NAME)

push-amd64: build-amd64
	podman push $(IMAGE_NAME)-amd64

push-arm64: build-arm64
	podman push $(IMAGE_NAME)-arm64

# Remove existing manifests
.PHONY: remove-manifests
remove-manifests:
	podman manifest exists $(IMAGE_NAME) && podman manifest rm $(IMAGE_NAME) || true
	podman manifest exists $(IMAGE_NAME)-$(VERSION) && podman manifest rm $(IMAGE_NAME)-$(VERSION) || true

# Create and push multi-arch manifest
.PHONY: push-manifest
push-manifest: push-amd64 push-arm64 remove-manifests
	podman manifest create $(IMAGE_NAME)-$(VERSION) $(IMAGE_NAME)-amd64 $(IMAGE_NAME)-arm64
	podman manifest push --all $(IMAGE_NAME)-$(VERSION) docker://$(IMAGE_NAME)-$(VERSION)

# ERPNext builds
.PHONY: erpnext erpnext-amd64 erpnext-arm64
erpnext:
	./s2i-podman.sh test/erpnext $(ERP_IMAGE_NAME) $(IMAGE_NAME)

erpnext-amd64: build-amd64
	./s2i-podman.sh --arch amd64 test/erpnext $(ERP_IMAGE_NAME)-amd64 $(IMAGE_NAME)-amd64 

erpnext-arm64: build-arm64
	./s2i-podman.sh --arch arm64 test/erpnext $(ERP_IMAGE_NAME)-arm64 $(IMAGE_NAME)-arm64 

# Remove ERPNext manifests
.PHONY: remove-erpnext-manifests
remove-erpnext-manifests:
	podman manifest exists $(ERP_IMAGE_NAME) && podman manifest rm $(ERP_IMAGE_NAME) || true
	podman manifest exists $(ERP_IMAGE_NAME)-$(VERSION) && podman manifest rm $(ERP_IMAGE_NAME)-$(VERSION) || true

# Create and push ERPNext multi-arch manifest
.PHONY: erpnext-manifest
erpnext-manifest: erpnext-amd64 erpnext-arm64 remove-erpnext-manifests push-erpnext

# Push ERPNext images
.PHONY: push-erpnext
push-erpnext:
	podman push $(ERP_IMAGE_NAME)-amd64
	podman push $(ERP_IMAGE_NAME)-arm64

	podman manifest create $(ERP_IMAGE_NAME) $(ERP_IMAGE_NAME)-amd64 $(ERP_IMAGE_NAME)-arm64
	podman manifest push --all $(ERP_IMAGE_NAME) docker://$(ERP_IMAGE_NAME)

# Clean up images and manifests
.PHONY: clean clean-manifests
clean:
	podman rmi -f $(IMAGE_NAME) $(IMAGE_NAME)-amd64 $(IMAGE_NAME)-arm64 $(ERP_IMAGE_NAME) $(ERP_IMAGE_NAME)-amd64 $(ERP_IMAGE_NAME)-arm64 || true

clean-manifests: remove-manifests remove-erpnext-manifests
