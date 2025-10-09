# Configuration
REGISTRY=docker.io
REPO=vyogo
FRAPPE_VERSION?=develop
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
	podman build -t $(IMAGE_NAME) .  --build-arg FRAPPE_BRANCH=$(FRAPPE_VERSION)

# Build for AMD64
.PHONY: build-amd64
build-amd64:
	podman build --platform=linux/amd64 -t $(IMAGE_NAME)-amd64 .  --build-arg FRAPPE_BRANCH=$(FRAPPE_VERSION)

# Build for ARM64
.PHONY: build-arm64
build-arm64:
	podman build --platform=linux/arm64 -t $(IMAGE_NAME)-arm64 .  --build-arg FRAPPE_BRANCH=$(FRAPPE_VERSION)

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
	podman manifest exists $(IMAGE_NAME) && podman manifest rm $(IMAGE_NAME) || true
# Create and push multi-arch manifest
.PHONY: push-manifest
push-manifest: push-amd64 push-arm64 remove-manifests
	# podman manifest create $(IMAGE_NAME)-$(FRAPPE_VERSION) $(IMAGE_NAME)-amd64 $(IMAGE_NAME)-arm64
	# podman manifest push --all $(IMAGE_NAME)-$(FRAPPE_VERSION) docker://$(IMAGE_NAME)-$(FRAPPE_VERSION)
	podman manifest create $(IMAGE_NAME)  $(IMAGE_NAME)-amd64 $(IMAGE_NAME)-arm64
	podman manifest push --all $(IMAGE_NAME)  docker://$(IMAGE_NAME)


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

# Frappe CRM builds - modified version
.PHONY: frappe-crm-develop frappe-crm-develop-amd64 frappe-crm-develop-arm64
.PHONY: frappe-crm-v1392 frappe-crm-v1392-amd64 frappe-crm-v1392-arm64

# CRM develop version
frappe-crm-develop:
	./s2i-podman.sh test/frappe-crm-develop $(CRM_IMAGE_NAME)-develop $(IMAGE_NAME) --frappe-branch=$(FRAPPE_VERSION)

frappe-crm-develop-amd64: build-amd64
	./s2i-podman.sh --arch amd64 test/frappe-crm-develop $(CRM_IMAGE_NAME)-develop-amd64 $(IMAGE_NAME)-amd64 --frappe-branch=$(FRAPPE_VERSION)

frappe-crm-develop-arm64: build-arm64
	./s2i-podman.sh --arch arm64 test/frappe-crm-develop $(CRM_IMAGE_NAME)-develop-arm64 $(IMAGE_NAME)-arm64 --frappe-branch=$(FRAPPE_VERSION)

# CRM v1.39.2 version
frappe-crm-v1392:
	./s2i-podman.sh test/frappe-crm-v1.39.2 $(CRM_IMAGE_NAME)-v1392 $(IMAGE_NAME) --frappe-branch=$(FRAPPE_VERSION)

frappe-crm-v1392-amd64: build-amd64
	./s2i-podman.sh --arch amd64 test/frappe-crm-v1.39.2 $(CRM_IMAGE_NAME)-v1392-amd64 $(IMAGE_NAME)-amd64 --frappe-branch=$(FRAPPE_VERSION)

frappe-crm-v1392-arm64: build-arm64
	./s2i-podman.sh --arch arm64 test/frappe-crm-v1.39.2 $(CRM_IMAGE_NAME)-v1392-arm64 $(IMAGE_NAME)-arm64 --frappe-branch=$(FRAPPE_VERSION)

# Remove Frappe CRM manifests
.PHONY: remove-frappe-crm-manifests
remove-frappe-crm-manifests:
	podman manifest exists $(CRM_IMAGE_NAME)-develop && podman manifest rm  $(CRM_IMAGE_NAME)-develop || true
	podman manifest exists  $(CRM_IMAGE_NAME)-v1392 && podman manifest rm  $(CRM_IMAGE_NAME)-v1392 || true

# Create and push Frappe CRM multi-arch manifest for develop
.PHONY: frappe-crm-develop-manifest
frappe-crm-develop-manifest: frappe-crm-develop-amd64 frappe-crm-develop-arm64 remove-frappe-crm-manifests
	podman push $(CRM_IMAGE_NAME)-develop-amd64
	podman push $(CRM_IMAGE_NAME)-develop-arm64
	podman manifest create $(CRM_IMAGE_NAME)-develop $(CRM_IMAGE_NAME)-develop-amd64 $(CRM_IMAGE_NAME)-develop-arm64
	podman manifest push --all $(CRM_IMAGE_NAME)-develop docker://$(CRM_IMAGE_NAME)-develop

# Create and push Frappe CRM multi-arch manifest for v1.39.2
.PHONY: frappe-crm-v1392-manifest
frappe-crm-v1392-manifest: frappe-crm-v1392-amd64 frappe-crm-v1392-arm64 remove-frappe-crm-manifests
	podman push $(CRM_IMAGE_NAME)-v1392-amd64
	podman push $(CRM_IMAGE_NAME)-v1392-arm64
	podman manifest create $(CRM_IMAGE_NAME)-v1392 $(CRM_IMAGE_NAME)-v1392-amd64 $(CRM_IMAGE_NAME)-v1392-arm64
	podman manifest push --all $(CRM_IMAGE_NAME)-v1392 docker://$(CRM_IMAGE_NAME)-v1392
