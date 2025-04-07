# Configuration
REGISTRY=docker.io
REPO=vyogo
FRAPPE_VERSION?=develop
IMAGE_NAME=$(REGISTRY)/$(REPO)/frappe:s2i-$(FRAPPE_VERSION)
ERP_IMAGE_NAME=$(REGISTRY)/$(REPO)/erpnext:sne-$(FRAPPE_VERSION)

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
	podman build -t $(IMAGE_NAME) .  --build-arg FRAPPE_BRANCH=$(FRAPPE_VERSION)

# Build for AMD64
.PHONY: build-amd64
build-amd64:
	podman build --arch=amd64 -t $(IMAGE_NAME)-amd64 .  --build-arg FRAPPE_BRANCH=$(FRAPPE_VERSION)

# Build for ARM64
.PHONY: build-arm64
build-arm64:
	podman build --arch=arm64 -t $(IMAGE_NAME)-arm64 .  --build-arg FRAPPE_BRANCH=$(FRAPPE_VERSION)

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
	podman manifest exists $(IMAGE_NAME)-$(FRAPPE_VERSION) && podman manifest rm $(IMAGE_NAME)-$(FRAPPE_VERSION) || true

# Create and push multi-arch manifest
.PHONY: push-manifest
push-manifest: push-amd64 push-arm64 remove-manifests
	podman manifest create $(IMAGE_NAME)-$(FRAPPE_VERSION) $(IMAGE_NAME)-amd64 $(IMAGE_NAME)-arm64
	podman manifest push --all $(IMAGE_NAME)-$(FRAPPE_VERSION) docker://$(IMAGE_NAME)-$(FRAPPE_VERSION)

# ERPNext builds
.PHONY: erpnext erpnext-amd64 erpnext-arm64
erpnext:
	./s2i-podman.sh test/erpnext-$(FRAPPE_VERSION) $(ERP_IMAGE_NAME) $(IMAGE_NAME) --frappe-branch=$(FRAPPE_VERSION)

erpnext-amd64: build-amd64
	./s2i-podman.sh --arch amd64 test/erpnext-$(FRAPPE_VERSION) $(ERP_IMAGE_NAME)-amd64 $(IMAGE_NAME)-amd64 --frappe-branch=$(FRAPPE_VERSION)

erpnext-arm64: build-arm64
	./s2i-podman.sh --arch arm64 test/erpnext-$(FRAPPE_VERSION) $(ERP_IMAGE_NAME)-arm64 $(IMAGE_NAME)-arm64 --frappe-branch=$(FRAPPE_VERSION)

# Remove ERPNext manifests
.PHONY: remove-erpnext-manifests
remove-erpnext-manifests:
	podman manifest exists $(ERP_IMAGE_NAME) && podman manifest rm $(ERP_IMAGE_NAME) || true
	podman manifest exists $(ERP_IMAGE_NAME)-$(FRAPPE_VERSION) && podman manifest rm $(ERP_IMAGE_NAME)-$(FRAPPE_VERSION) || true

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
# Frappe CRM builds
.PHONY: frappe-crm frappe-crm-amd64 frappe-crm-arm64
frappe-crm:
	./s2i-podman.sh test/frappe-crm-$(FRAPPE_VERSION) $(IMAGE_NAME)-crm $(IMAGE_NAME) --frappe-branch=$(FRAPPE_VERSION)

frappe-crm-amd64: build-amd64
	./s2i-podman.sh --arch amd64 test/frappe-crm-$(FRAPPE_VERSION) $(IMAGE_NAME)-crm-amd64 $(IMAGE_NAME)-amd64 --frappe-branch=$(FRAPPE_VERSION)

frappe-crm-arm64: build-arm64
	./s2i-podman.sh --arch arm64 test/frappe-crm-$(FRAPPE_VERSION) $(IMAGE_NAME)-crm-arm64 $(IMAGE_NAME)-arm64 --frappe-branch=$(FRAPPE_VERSION)

# Remove Frappe CRM manifests
.PHONY: remove-frappe-crm-manifests
remove-frappe-crm-manifests:
	podman manifest exists $(IMAGE_NAME)-crm && podman manifest rm $(IMAGE_NAME)-crm || true
	podman manifest exists $(IMAGE_NAME)-crm-$(FRAPPE_VERSION) && podman manifest rm $(IMAGE_NAME)-crm-$(FRAPPE_VERSION) || true

# Create and push Frappe CRM multi-arch manifest
.PHONY: frappe-crm-manifest
frappe-crm-manifest: frappe-crm-amd64 frappe-crm-arm64 remove-frappe-crm-manifests push-frappe-crm

# Push Frappe CRM images
.PHONY: push-frappe-crm
push-frappe-crm:
	podman push $(IMAGE_NAME)-crm-amd64
	podman push $(IMAGE_NAME)-crm-arm64

	podman manifest create $(IMAGE_NAME)-crm $(IMAGE_NAME)-crm-amd64 $(IMAGE_NAME)-crm-arm64
	podman manifest push --all $(IMAGE_NAME)-crm docker://$(IMAGE_NAME)-crm