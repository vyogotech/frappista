# Configuration
REGISTRY=docker.io
REPO=vyogo
FRAPPE_VERSION?=version-16
FRAPPE_BRANCH?=$(FRAPPE_VERSION)
IMAGE_TAG?=$(FRAPPE_VERSION)
# Local image names (no registry prefix)
LOCAL_IMAGE_NAME=localhost/frappe:s2i-$(IMAGE_TAG)
LOCAL_ERP_IMAGE_NAME=localhost/erpnext:sne-$(IMAGE_TAG)
LOCAL_CRM_IMAGE_NAME=localhost/crm:sne-$(IMAGE_TAG)
LOCAL_CENTRAL_SITE_IMAGE_NAME=localhost/central-site:sne-$(IMAGE_TAG)
# Registry image names (with registry prefix for pushing)
IMAGE_NAME=$(REGISTRY)/$(REPO)/frappe:s2i-$(IMAGE_TAG)
ERP_IMAGE_NAME=$(REGISTRY)/$(REPO)/erpnext:sne-$(IMAGE_TAG)
CRM_IMAGE_NAME=$(REGISTRY)/$(REPO)/crm:sne-$(IMAGE_TAG)
CENTRAL_SITE_IMAGE_NAME=$(REGISTRY)/$(REPO)/central-site:sne-$(IMAGE_TAG)

# Cache configuration
CACHE_REPO=$(REGISTRY)/$(REPO)/frappista-cache-$(IMAGE_TAG)
CACHE_FLAGS?=# e.g. --layers --cache-from=$(CACHE_REPO) --cache-to=$(CACHE_REPO)

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
	@echo " central-site - Build central-site image (current arch)"
	@echo " central-site-amd64 - Build central-site for AMD64"
	@echo " central-site-arm64 - Build central-site for ARM64"
	@echo " clean - Remove all images"

# Build for current architecture
.PHONY: build
build:
	podman build --layers $(CACHE_FLAGS) -t $(LOCAL_IMAGE_NAME) .  --build-arg FRAPPE_BRANCH=$(FRAPPE_BRANCH)

# Build for AMD64
.PHONY: build-amd64
build-amd64:
	podman build --layers $(CACHE_FLAGS) --platform=linux/amd64 -t $(LOCAL_IMAGE_NAME)-amd64 .  --build-arg FRAPPE_BRANCH=$(FRAPPE_BRANCH)

# Build for ARM64
.PHONY: build-arm64
build-arm64:
	@echo "Building $(LOCAL_IMAGE_NAME)-arm64 with FRAPPE_VERSION=$(FRAPPE_VERSION)"
	podman build --layers $(CACHE_FLAGS) --platform=linux/arm64 -t $(LOCAL_IMAGE_NAME)-arm64 .  --build-arg FRAPPE_BRANCH=$(FRAPPE_BRANCH)
	@echo "Build completed. Verifying image was created:"
	podman images $(LOCAL_IMAGE_NAME)-arm64

# Push images
.PHONY: push push-amd64 push-arm64 push-only-amd64 push-only-arm64
push:
	podman tag $(LOCAL_IMAGE_NAME) $(IMAGE_NAME)
	podman push $(IMAGE_NAME)

# Push targets that rebuild (for backwards compatibility)
push-amd64: build-amd64 push-only-amd64
push-arm64: build-arm64 push-only-arm64

# Push targets that only tag and push (no rebuild)
push-only-amd64:
	@echo "Tagging and pushing AMD64 image..."
	podman tag $(LOCAL_IMAGE_NAME)-amd64 $(IMAGE_NAME)-amd64
	podman push $(IMAGE_NAME)-amd64
	@echo "Successfully pushed $(IMAGE_NAME)-amd64"

push-only-arm64:
	@echo "Tagging and pushing ARM64 image..."
	podman tag $(LOCAL_IMAGE_NAME)-arm64 $(IMAGE_NAME)-arm64
	podman push $(IMAGE_NAME)-arm64
	@echo "Successfully pushed $(IMAGE_NAME)-arm64"

# Remove existing manifests
.PHONY: remove-manifests
remove-manifests:
	podman manifest exists $(IMAGE_NAME) && podman manifest rm $(IMAGE_NAME) || true
	podman manifest exists $(IMAGE_NAME)-$(FRAPPE_VERSION) && podman manifest rm $(IMAGE_NAME)-$(FRAPPE_VERSION) || true

# Create and push multi-arch manifest (assumes images already built)
.PHONY: push-manifest
push-manifest: remove-manifests push-only-amd64 push-only-arm64
	@echo "Creating multi-arch manifest for $(IMAGE_NAME)..."
	podman manifest create $(IMAGE_NAME) $(IMAGE_NAME)-amd64 $(IMAGE_NAME)-arm64
	@echo "Pushing manifest..."
	podman manifest push --all $(IMAGE_NAME) docker://$(IMAGE_NAME)
	@echo "Successfully pushed multi-arch manifest $(IMAGE_NAME)"

# Create manifest from images already in registry (no local images needed)
.PHONY: create-frappe-manifest
create-frappe-manifest: remove-manifests
	@echo "Creating multi-arch manifest for $(IMAGE_NAME) from registry images..."
	podman manifest create $(IMAGE_NAME) $(IMAGE_NAME)-amd64 $(IMAGE_NAME)-arm64
	@echo "Pushing manifest..."
	podman manifest push --all $(IMAGE_NAME) docker://$(IMAGE_NAME)
	@echo "Successfully pushed multi-arch manifest $(IMAGE_NAME)"


# ERPNext builds
.PHONY: erpnext erpnext-amd64 erpnext-arm64
erpnext:
	./s2i-podman.sh test/erpnext $(LOCAL_ERP_IMAGE_NAME) $(LOCAL_IMAGE_NAME) --frappe-branch=$(FRAPPE_BRANCH)

erpnext-amd64: build-amd64
	./s2i-podman.sh --arch amd64 test/erpnext $(LOCAL_ERP_IMAGE_NAME)-amd64 $(LOCAL_IMAGE_NAME)-amd64 --frappe-branch=$(FRAPPE_BRANCH)

erpnext-arm64: build-arm64
	./s2i-podman.sh --arch arm64 test/erpnext $(LOCAL_ERP_IMAGE_NAME)-arm64 $(IMAGE_NAME)-arm64 --frappe-branch=$(FRAPPE_BRANCH)

# Remove ERPNext manifests
.PHONY: remove-erpnext-manifests
remove-erpnext-manifests:
	podman manifest exists $(ERP_IMAGE_NAME) && podman manifest rm $(ERP_IMAGE_NAME) || true
	podman manifest exists $(ERP_IMAGE_NAME)-$(FRAPPE_VERSION) && podman manifest rm $(ERP_IMAGE_NAME)-$(FRAPPE_VERSION) || true

# Create and push ERPNext multi-arch manifest (assumes images already built)
.PHONY: erpnext-manifest
erpnext-manifest: remove-erpnext-manifests push-erpnext

# Create ERPNext manifest from images already in registry (no local images needed)
.PHONY: create-erpnext-manifest
create-erpnext-manifest: remove-erpnext-manifests
	@echo "Creating multi-arch manifest for $(ERP_IMAGE_NAME) from registry images..."
	podman manifest create $(ERP_IMAGE_NAME) $(ERP_IMAGE_NAME)-amd64 $(ERP_IMAGE_NAME)-arm64
	@echo "Pushing manifest..."
	podman manifest push --all $(ERP_IMAGE_NAME) docker://$(ERP_IMAGE_NAME)
	@echo "Successfully pushed multi-arch manifest $(ERP_IMAGE_NAME)"

# Push ERPNext images (only tag and push, no rebuild)
.PHONY: push-erpnext
push-erpnext:
	@echo "Tagging and pushing ERPNext AMD64 image..."
	podman tag $(LOCAL_ERP_IMAGE_NAME)-amd64 $(ERP_IMAGE_NAME)-amd64
	podman push $(ERP_IMAGE_NAME)-amd64
	@echo "Successfully pushed $(ERP_IMAGE_NAME)-amd64"
	
	@echo "Tagging and pushing ERPNext ARM64 image..."
	podman tag $(LOCAL_ERP_IMAGE_NAME)-arm64 $(ERP_IMAGE_NAME)-arm64
	podman push $(ERP_IMAGE_NAME)-arm64
	@echo "Successfully pushed $(ERP_IMAGE_NAME)-arm64"

	@echo "Creating multi-arch manifest for $(ERP_IMAGE_NAME)..."
	podman manifest create $(ERP_IMAGE_NAME) $(ERP_IMAGE_NAME)-amd64 $(ERP_IMAGE_NAME)-arm64
	@echo "Pushing manifest..."
	podman manifest push --all $(ERP_IMAGE_NAME) docker://$(ERP_IMAGE_NAME)
	@echo "Successfully pushed multi-arch manifest $(ERP_IMAGE_NAME)"

# Clean up images and manifests
.PHONY: clean clean-manifests
clean:
	podman rmi -f $(LOCAL_IMAGE_NAME) $(LOCAL_IMAGE_NAME)-amd64 $(LOCAL_IMAGE_NAME)-arm64 || true
	podman rmi -f $(LOCAL_ERP_IMAGE_NAME) $(LOCAL_ERP_IMAGE_NAME)-amd64 $(LOCAL_ERP_IMAGE_NAME)-arm64 || true
	podman rmi -f $(LOCAL_CENTRAL_SITE_IMAGE_NAME) $(LOCAL_CENTRAL_SITE_IMAGE_NAME)-amd64 $(LOCAL_CENTRAL_SITE_IMAGE_NAME)-arm64 || true
	podman rmi -f $(IMAGE_NAME) $(IMAGE_NAME)-amd64 $(IMAGE_NAME)-arm64 || true
	podman rmi -f $(ERP_IMAGE_NAME) $(ERP_IMAGE_NAME)-amd64 $(ERP_IMAGE_NAME)-arm64 || true
	podman rmi -f $(CENTRAL_SITE_IMAGE_NAME) $(CENTRAL_SITE_IMAGE_NAME)-amd64 $(CENTRAL_SITE_IMAGE_NAME)-arm64 || true

clean-manifests: remove-manifests remove-erpnext-manifests

# Frappe CRM builds - modified version
.PHONY: frappe-crm-develop frappe-crm-develop-amd64 frappe-crm-develop-arm64
.PHONY: frappe-crm-v1392 frappe-crm-v1392-amd64 frappe-crm-v1392-arm64

# CRM develop version
frappe-crm-develop:
	./s2i-podman.sh test/frappe-crm-develop $(LOCAL_CRM_IMAGE_NAME)-develop $(LOCAL_IMAGE_NAME) --frappe-branch=$(FRAPPE_BRANCH)

frappe-crm-develop-amd64: build-amd64
	./s2i-podman.sh --arch amd64 test/frappe-crm-develop $(LOCAL_CRM_IMAGE_NAME)-develop-amd64 $(LOCAL_IMAGE_NAME)-amd64 --frappe-branch=$(FRAPPE_BRANCH)

frappe-crm-develop-arm64: build-arm64
	./s2i-podman.sh --arch arm64 test/frappe-crm-develop $(LOCAL_CRM_IMAGE_NAME)-develop-arm64 $(LOCAL_IMAGE_NAME)-arm64 --frappe-branch=$(FRAPPE_BRANCH)

# CRM v1.39.2 version
frappe-crm-v1392:
	./s2i-podman.sh test/frappe-crm-v1.39.2 $(LOCAL_CRM_IMAGE_NAME)-v1392 $(LOCAL_IMAGE_NAME) --frappe-branch=$(FRAPPE_BRANCH)

frappe-crm-v1392-amd64: build-amd64
	./s2i-podman.sh --arch amd64 test/frappe-crm-v1.39.2 $(LOCAL_CRM_IMAGE_NAME)-v1392-amd64 $(LOCAL_IMAGE_NAME)-amd64 --frappe-branch=$(FRAPPE_BRANCH)

frappe-crm-v1392-arm64: build-arm64
	./s2i-podman.sh --arch arm64 test/frappe-crm-v1.39.2 $(LOCAL_CRM_IMAGE_NAME)-v1392-arm64 $(LOCAL_IMAGE_NAME)-arm64 --frappe-branch=$(FRAPPE_BRANCH)

# Remove Frappe CRM manifests
.PHONY: remove-frappe-crm-manifests
remove-frappe-crm-manifests:
	podman manifest exists $(CRM_IMAGE_NAME)-develop && podman manifest rm  $(CRM_IMAGE_NAME)-develop || true
	podman manifest exists  $(CRM_IMAGE_NAME)-v1392 && podman manifest rm  $(CRM_IMAGE_NAME)-v1392 || true

# Create and push Frappe CRM multi-arch manifest for develop (assumes images already built)
.PHONY: frappe-crm-develop-manifest
frappe-crm-develop-manifest: remove-frappe-crm-manifests
	@echo "Tagging and pushing Frappe CRM develop AMD64..."
	podman tag $(LOCAL_CRM_IMAGE_NAME)-develop-amd64 $(CRM_IMAGE_NAME)-develop-amd64
	podman push $(CRM_IMAGE_NAME)-develop-amd64
	@echo "Tagging and pushing Frappe CRM develop ARM64..."
	podman tag $(LOCAL_CRM_IMAGE_NAME)-develop-arm64 $(CRM_IMAGE_NAME)-develop-arm64
	podman push $(CRM_IMAGE_NAME)-develop-arm64
	@echo "Creating multi-arch manifest..."
	podman manifest create $(CRM_IMAGE_NAME)-develop $(CRM_IMAGE_NAME)-develop-amd64 $(CRM_IMAGE_NAME)-develop-arm64
	podman manifest push --all $(CRM_IMAGE_NAME)-develop docker://$(CRM_IMAGE_NAME)-develop
	@echo "Successfully pushed $(CRM_IMAGE_NAME)-develop"

# Create and push Frappe CRM multi-arch manifest for v1.39.2 (assumes images already built)
.PHONY: frappe-crm-v1392-manifest
frappe-crm-v1392-manifest: remove-frappe-crm-manifests
	@echo "Tagging and pushing Frappe CRM v1.39.2 AMD64..."
	podman tag $(LOCAL_CRM_IMAGE_NAME)-v1392-amd64 $(CRM_IMAGE_NAME)-v1392-amd64
	podman push $(CRM_IMAGE_NAME)-v1392-amd64
	@echo "Tagging and pushing Frappe CRM v1.39.2 ARM64..."
	podman tag $(LOCAL_CRM_IMAGE_NAME)-v1392-arm64 $(CRM_IMAGE_NAME)-v1392-arm64
	podman push $(CRM_IMAGE_NAME)-v1392-arm64
	@echo "Creating multi-arch manifest..."
	podman manifest create $(CRM_IMAGE_NAME)-v1392 $(CRM_IMAGE_NAME)-v1392-amd64 $(CRM_IMAGE_NAME)-v1392-arm64
	podman manifest push --all $(CRM_IMAGE_NAME)-v1392 docker://$(CRM_IMAGE_NAME)-v1392
	@echo "Successfully pushed $(CRM_IMAGE_NAME)-v1392"

# Central-site builds — layers 3 apps on top of the ERPNext SNE image via S2I.
# The central-site repo (with submodules checked out) is the S2I source.
# apps.json uses "source" fields to copy apps from checked-out submodule dirs.
# Set CENTRAL_SITE_SRC to the path of your central-site checkout (with submodules inited).
CENTRAL_SITE_SRC?=../central-site
.PHONY: central-site central-site-amd64 central-site-arm64
central-site:
	./s2i-podman.sh $(CENTRAL_SITE_SRC) $(LOCAL_CENTRAL_SITE_IMAGE_NAME) $(ERP_IMAGE_NAME) --frappe-branch=$(FRAPPE_BRANCH)

central-site-amd64:
	./s2i-podman.sh --arch amd64 $(CENTRAL_SITE_SRC) $(LOCAL_CENTRAL_SITE_IMAGE_NAME)-amd64 $(ERP_IMAGE_NAME) --frappe-branch=$(FRAPPE_BRANCH)

central-site-arm64:
	./s2i-podman.sh --arch arm64 $(CENTRAL_SITE_SRC) $(LOCAL_CENTRAL_SITE_IMAGE_NAME)-arm64 $(ERP_IMAGE_NAME) --frappe-branch=$(FRAPPE_BRANCH)

# Remove central-site manifests
.PHONY: remove-central-site-manifests
remove-central-site-manifests:
	podman manifest exists $(CENTRAL_SITE_IMAGE_NAME) && podman manifest rm $(CENTRAL_SITE_IMAGE_NAME) || true

# Push central-site multi-arch manifest (assumes images already built)
.PHONY: push-central-site
push-central-site: remove-central-site-manifests
	@echo "Tagging and pushing central-site AMD64..."
	podman tag $(LOCAL_CENTRAL_SITE_IMAGE_NAME)-amd64 $(CENTRAL_SITE_IMAGE_NAME)-amd64
	podman push $(CENTRAL_SITE_IMAGE_NAME)-amd64
	@echo "Tagging and pushing central-site ARM64..."
	podman tag $(LOCAL_CENTRAL_SITE_IMAGE_NAME)-arm64 $(CENTRAL_SITE_IMAGE_NAME)-arm64
	podman push $(CENTRAL_SITE_IMAGE_NAME)-arm64
	@echo "Creating multi-arch manifest..."
	podman manifest create $(CENTRAL_SITE_IMAGE_NAME) $(CENTRAL_SITE_IMAGE_NAME)-amd64 $(CENTRAL_SITE_IMAGE_NAME)-arm64
	podman manifest push --all $(CENTRAL_SITE_IMAGE_NAME) docker://$(CENTRAL_SITE_IMAGE_NAME)
	@echo "Successfully pushed $(CENTRAL_SITE_IMAGE_NAME)"
