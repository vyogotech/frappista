# Configuration
REGISTRY=docker.io
REPO=vyogo
FRAPPE_VERSION?=version-16
CONTAINER ?= $(shell command -v podman 2>/dev/null || command -v docker 2>/dev/null)
CONTAINERFILE ?= Containerfile

ifeq ($(CONTAINER),)
$(error No container engine found. Install podman or docker.)
endif

# Local image names (no registry prefix)
LOCAL_IMAGE_NAME=localhost/frappe:s2i-$(FRAPPE_VERSION)
LOCAL_ERP_IMAGE_NAME=localhost/erpnext:sne-$(FRAPPE_VERSION)
LOCAL_CRM_IMAGE_NAME=localhost/crm:sne-$(FRAPPE_VERSION)
# Registry image names (with registry prefix for pushing)
IMAGE_NAME=$(REGISTRY)/$(REPO)/frappe:s2i-$(FRAPPE_VERSION)
ERP_IMAGE_NAME=$(REGISTRY)/$(REPO)/erpnext:sne-$(FRAPPE_VERSION)
CRM_IMAGE_NAME=$(REGISTRY)/$(REPO)/crm:sne-$(FRAPPE_VERSION)

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
	$(CONTAINER) build -f $(CONTAINERFILE) -t $(LOCAL_IMAGE_NAME) . --build-arg FRAPPE_BRANCH=$(FRAPPE_VERSION)

# Build for AMD64
.PHONY: build-amd64
build-amd64:
	$(CONTAINER) build -f $(CONTAINERFILE) --platform=linux/amd64 -t $(LOCAL_IMAGE_NAME)-amd64 . --build-arg FRAPPE_BRANCH=$(FRAPPE_VERSION)

# Build for ARM64
.PHONY: build-arm64
build-arm64:
	@echo "Building $(LOCAL_IMAGE_NAME)-arm64 with FRAPPE_VERSION=$(FRAPPE_VERSION)"
	$(CONTAINER) build -f $(CONTAINERFILE) --platform=linux/arm64 -t $(LOCAL_IMAGE_NAME)-arm64 . --build-arg FRAPPE_BRANCH=$(FRAPPE_VERSION)
	@echo "Build completed. Verifying image was created:"
	$(CONTAINER) images $(LOCAL_IMAGE_NAME)-arm64

# Push images
.PHONY: push push-amd64 push-arm64 push-only-amd64 push-only-arm64
push:
	$(CONTAINER) tag $(LOCAL_IMAGE_NAME) $(IMAGE_NAME)
	$(CONTAINER) push $(IMAGE_NAME)

# Push targets that rebuild (for backwards compatibility)
push-amd64: build-amd64 push-only-amd64
push-arm64: build-arm64 push-only-arm64

# Push targets that only tag and push (no rebuild)
push-only-amd64:
	@echo "Tagging and pushing AMD64 image..."
	$(CONTAINER) tag $(LOCAL_IMAGE_NAME)-amd64 $(IMAGE_NAME)-amd64
	$(CONTAINER) push $(IMAGE_NAME)-amd64
	@echo "Successfully pushed $(IMAGE_NAME)-amd64"

push-only-arm64:
	@echo "Tagging and pushing ARM64 image..."
	$(CONTAINER) tag $(LOCAL_IMAGE_NAME)-arm64 $(IMAGE_NAME)-arm64
	$(CONTAINER) push $(IMAGE_NAME)-arm64
	@echo "Successfully pushed $(IMAGE_NAME)-arm64"

# Remove existing manifests
.PHONY: remove-manifests
remove-manifests:
	$(CONTAINER) manifest exists $(IMAGE_NAME) && $(CONTAINER) manifest rm $(IMAGE_NAME) || true
	$(CONTAINER) manifest exists $(IMAGE_NAME)-$(FRAPPE_VERSION) && $(CONTAINER) manifest rm $(IMAGE_NAME)-$(FRAPPE_VERSION) || true

# Create and push multi-arch manifest (assumes images already built)
.PHONY: push-manifest
push-manifest: remove-manifests push-only-amd64 push-only-arm64
	@echo "Creating multi-arch manifest for $(IMAGE_NAME)..."
	$(CONTAINER) manifest create $(IMAGE_NAME) $(IMAGE_NAME)-amd64 $(IMAGE_NAME)-arm64
	@echo "Pushing manifest..."
	$(CONTAINER) manifest push --all $(IMAGE_NAME) docker://$(IMAGE_NAME)
	@echo "Successfully pushed multi-arch manifest $(IMAGE_NAME)"


# ERPNext builds
.PHONY: erpnext erpnext-amd64 erpnext-arm64
erpnext:
	./s2i-podman.sh test/erpnext $(LOCAL_ERP_IMAGE_NAME) $(LOCAL_IMAGE_NAME) --frappe-branch=$(FRAPPE_VERSION)

erpnext-amd64: build-amd64
	./s2i-podman.sh --arch amd64 test/erpnext $(LOCAL_ERP_IMAGE_NAME)-amd64 $(LOCAL_IMAGE_NAME)-amd64 --frappe-branch=$(FRAPPE_VERSION)

erpnext-arm64: build-arm64
	./s2i-podman.sh --arch arm64 test/erpnext $(LOCAL_ERP_IMAGE_NAME)-arm64 $(IMAGE_NAME)-arm64 --frappe-branch=$(FRAPPE_VERSION)

# Remove ERPNext manifests
.PHONY: remove-erpnext-manifests
remove-erpnext-manifests:
	$(CONTAINER) manifest exists $(ERP_IMAGE_NAME) && $(CONTAINER) manifest rm $(ERP_IMAGE_NAME) || true
	$(CONTAINER) manifest exists $(ERP_IMAGE_NAME)-$(FRAPPE_VERSION) && $(CONTAINER) manifest rm $(ERP_IMAGE_NAME)-$(FRAPPE_VERSION) || true

# Create and push ERPNext multi-arch manifest (assumes images already built)
.PHONY: erpnext-manifest
erpnext-manifest: remove-erpnext-manifests push-erpnext

# Push ERPNext images (only tag and push, no rebuild)
.PHONY: push-erpnext
push-erpnext:
	@echo "Tagging and pushing ERPNext AMD64 image..."
	$(CONTAINER) tag $(LOCAL_ERP_IMAGE_NAME)-amd64 $(ERP_IMAGE_NAME)-amd64
	$(CONTAINER) push $(ERP_IMAGE_NAME)-amd64
	@echo "Successfully pushed $(ERP_IMAGE_NAME)-amd64"
	
	@echo "Tagging and pushing ERPNext ARM64 image..."
	$(CONTAINER) tag $(LOCAL_ERP_IMAGE_NAME)-arm64 $(ERP_IMAGE_NAME)-arm64
	$(CONTAINER) push $(ERP_IMAGE_NAME)-arm64
	@echo "Successfully pushed $(ERP_IMAGE_NAME)-arm64"

	@echo "Creating multi-arch manifest for $(ERP_IMAGE_NAME)..."
	$(CONTAINER) manifest create $(ERP_IMAGE_NAME) $(ERP_IMAGE_NAME)-amd64 $(ERP_IMAGE_NAME)-arm64
	@echo "Pushing manifest..."
	$(CONTAINER) manifest push --all $(ERP_IMAGE_NAME) docker://$(ERP_IMAGE_NAME)
	@echo "Successfully pushed multi-arch manifest $(ERP_IMAGE_NAME)"

# Clean up images and manifests
.PHONY: clean clean-manifests
clean:
	$(CONTAINER) rmi -f $(LOCAL_IMAGE_NAME) $(LOCAL_IMAGE_NAME)-amd64 $(LOCAL_IMAGE_NAME)-arm64 || true
	$(CONTAINER) rmi -f $(LOCAL_ERP_IMAGE_NAME) $(LOCAL_ERP_IMAGE_NAME)-amd64 $(LOCAL_ERP_IMAGE_NAME)-arm64 || true
	$(CONTAINER) rmi -f $(IMAGE_NAME) $(IMAGE_NAME)-amd64 $(IMAGE_NAME)-arm64 || true
	$(CONTAINER) rmi -f $(ERP_IMAGE_NAME) $(ERP_IMAGE_NAME)-amd64 $(ERP_IMAGE_NAME)-arm64 || true

clean-manifests: remove-manifests remove-erpnext-manifests

# Frappe CRM builds - modified version
.PHONY: frappe-crm-develop frappe-crm-develop-amd64 frappe-crm-develop-arm64
.PHONY: frappe-crm-v1392 frappe-crm-v1392-amd64 frappe-crm-v1392-arm64

# CRM develop version
frappe-crm-develop:
	./s2i-podman.sh test/frappe-crm-develop $(LOCAL_CRM_IMAGE_NAME)-develop $(LOCAL_IMAGE_NAME) --frappe-branch=$(FRAPPE_VERSION)

frappe-crm-develop-amd64: build-amd64
	./s2i-podman.sh --arch amd64 test/frappe-crm-develop $(LOCAL_CRM_IMAGE_NAME)-develop-amd64 $(LOCAL_IMAGE_NAME)-amd64 --frappe-branch=$(FRAPPE_VERSION)

frappe-crm-develop-arm64: build-arm64
	./s2i-podman.sh --arch arm64 test/frappe-crm-develop $(LOCAL_CRM_IMAGE_NAME)-develop-arm64 $(LOCAL_IMAGE_NAME)-arm64 --frappe-branch=$(FRAPPE_VERSION)

# CRM v1.39.2 version
frappe-crm-v1392:
	./s2i-podman.sh test/frappe-crm-v1.39.2 $(LOCAL_CRM_IMAGE_NAME)-v1392 $(LOCAL_IMAGE_NAME) --frappe-branch=$(FRAPPE_VERSION)

frappe-crm-v1392-amd64: build-amd64
	./s2i-podman.sh --arch amd64 test/frappe-crm-v1.39.2 $(LOCAL_CRM_IMAGE_NAME)-v1392-amd64 $(LOCAL_IMAGE_NAME)-amd64 --frappe-branch=$(FRAPPE_VERSION)

frappe-crm-v1392-arm64: build-arm64
	./s2i-podman.sh --arch arm64 test/frappe-crm-v1.39.2 $(LOCAL_CRM_IMAGE_NAME)-v1392-arm64 $(LOCAL_IMAGE_NAME)-arm64 --frappe-branch=$(FRAPPE_VERSION)

# Remove Frappe CRM manifests
.PHONY: remove-frappe-crm-manifests
remove-frappe-crm-manifests:
	$(CONTAINER) manifest exists $(CRM_IMAGE_NAME)-develop && $(CONTAINER) manifest rm  $(CRM_IMAGE_NAME)-develop || true
	$(CONTAINER) manifest exists  $(CRM_IMAGE_NAME)-v1392 && $(CONTAINER) manifest rm  $(CRM_IMAGE_NAME)-v1392 || true

# Create and push Frappe CRM multi-arch manifest for develop (assumes images already built)
.PHONY: frappe-crm-develop-manifest
frappe-crm-develop-manifest: remove-frappe-crm-manifests
	@echo "Tagging and pushing Frappe CRM develop AMD64..."
	$(CONTAINER) tag $(LOCAL_CRM_IMAGE_NAME)-develop-amd64 $(CRM_IMAGE_NAME)-develop-amd64
	$(CONTAINER) push $(CRM_IMAGE_NAME)-develop-amd64
	@echo "Tagging and pushing Frappe CRM develop ARM64..."
	$(CONTAINER) tag $(LOCAL_CRM_IMAGE_NAME)-develop-arm64 $(CRM_IMAGE_NAME)-develop-arm64
	$(CONTAINER) push $(CRM_IMAGE_NAME)-develop-arm64
	@echo "Creating multi-arch manifest..."
	$(CONTAINER) manifest create $(CRM_IMAGE_NAME)-develop $(CRM_IMAGE_NAME)-develop-amd64 $(CRM_IMAGE_NAME)-develop-arm64
	$(CONTAINER) manifest push --all $(CRM_IMAGE_NAME)-develop docker://$(CRM_IMAGE_NAME)-develop
	@echo "Successfully pushed $(CRM_IMAGE_NAME)-develop"

# Create and push Frappe CRM multi-arch manifest for v1.39.2 (assumes images already built)
.PHONY: frappe-crm-v1392-manifest
frappe-crm-v1392-manifest: remove-frappe-crm-manifests
	@echo "Tagging and pushing Frappe CRM v1.39.2 AMD64..."
	$(CONTAINER) tag $(LOCAL_CRM_IMAGE_NAME)-v1392-amd64 $(CRM_IMAGE_NAME)-v1392-amd64
	$(CONTAINER) push $(CRM_IMAGE_NAME)-v1392-amd64
	@echo "Tagging and pushing Frappe CRM v1.39.2 ARM64..."
	$(CONTAINER) tag $(LOCAL_CRM_IMAGE_NAME)-v1392-arm64 $(CRM_IMAGE_NAME)-v1392-arm64
	$(CONTAINER) push $(CRM_IMAGE_NAME)-v1392-arm64
	@echo "Creating multi-arch manifest..."
	$(CONTAINER) manifest create $(CRM_IMAGE_NAME)-v1392 $(CRM_IMAGE_NAME)-v1392-amd64 $(CRM_IMAGE_NAME)-v1392-arm64
	$(CONTAINER) manifest push --all $(CRM_IMAGE_NAME)-v1392 docker://$(CRM_IMAGE_NAME)-v1392
	@echo "Successfully pushed $(CRM_IMAGE_NAME)-v1392"
