# Configuration
REGISTRY=docker.io
REPO=vyogo
FRAPPE_VERSION?=develop
FRAPPE_BRANCH?=$(FRAPPE_VERSION)
IMAGE_TAG?=$(FRAPPE_VERSION)
CONTAINER ?= $(shell command -v podman 2>/dev/null || command -v docker 2>/dev/null)
CONTAINERFILE ?= Containerfile
CONTAINERFILE_PG ?= Containerfile.postgres

ifeq ($(CONTAINER),)
$(error No container engine found. Install podman or docker.)
endif

# Local image names (no registry prefix)
LOCAL_IMAGE_NAME=localhost/frappe:s2i-$(IMAGE_TAG)
LOCAL_IMAGE_NAME_PG=localhost/frappe:s2i-postgres-$(IMAGE_TAG)
LOCAL_FRAPPE_APP_IMAGE_NAME=localhost/frappe:sne-$(IMAGE_TAG)
LOCAL_ERP_IMAGE_NAME=localhost/erpnext:sne-$(IMAGE_TAG)
LOCAL_ERP_IMAGE_NAME_PG=localhost/erpnext:sne-postgres-$(IMAGE_TAG)
LOCAL_CRM_IMAGE_NAME=localhost/crm:sne-$(IMAGE_TAG)
# Registry image names (with registry prefix for pushing)
IMAGE_NAME=$(REGISTRY)/$(REPO)/frappe:s2i-$(IMAGE_TAG)
IMAGE_NAME_PG=$(REGISTRY)/$(REPO)/frappe:s2i-postgres-$(IMAGE_TAG)
FRAPPE_APP_IMAGE_NAME=$(REGISTRY)/$(REPO)/frappe:sne-$(IMAGE_TAG)
ERP_IMAGE_NAME=$(REGISTRY)/$(REPO)/erpnext:sne-$(IMAGE_TAG)
ERP_IMAGE_NAME_PG=$(REGISTRY)/$(REPO)/erpnext:sne-postgres-$(IMAGE_TAG)
CRM_IMAGE_NAME=$(REGISTRY)/$(REPO)/crm:sne-$(IMAGE_TAG)

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
	@echo " frappe-app - Build runnable Frappe image"
	@echo " frappe-app-amd64 - Build runnable Frappe for AMD64"
	@echo " frappe-app-arm64 - Build runnable Frappe for ARM64"
	@echo " erpnext - Build ERPNext image"
	@echo " erpnext-amd64 - Build ERPNext for AMD64"
	@echo " erpnext-arm64 - Build ERPNext for ARM64"
	@echo " clean - Remove all images"

# Build for current architecture
.PHONY: build
build:
	$(CONTAINER) build -f $(CONTAINERFILE) -t $(LOCAL_IMAGE_NAME) . --build-arg FRAPPE_BRANCH=$(FRAPPE_BRANCH) --build-arg TARGETARCH=$(shell uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')

# Build for AMD64
.PHONY: build-amd64
build-amd64:
	$(CONTAINER) build -f $(CONTAINERFILE) --platform=linux/amd64 -t $(LOCAL_IMAGE_NAME)-amd64 . --build-arg FRAPPE_BRANCH=$(FRAPPE_BRANCH) --build-arg TARGETARCH=amd64

# Build for ARM64
.PHONY: build-arm64
build-arm64:
	@echo "Building $(LOCAL_IMAGE_NAME)-arm64 with FRAPPE_VERSION=$(FRAPPE_VERSION)"
	$(CONTAINER) build -f $(CONTAINERFILE) --platform=linux/arm64 -t $(LOCAL_IMAGE_NAME)-arm64 . --build-arg FRAPPE_BRANCH=$(FRAPPE_BRANCH) --build-arg TARGETARCH=arm64
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
	$(CONTAINER) manifest exists $(IMAGE_NAME)-$(IMAGE_TAG) && $(CONTAINER) manifest rm $(IMAGE_NAME)-$(IMAGE_TAG) || true

# Create and push multi-arch manifest (assumes images already built)
.PHONY: push-manifest
push-manifest: remove-manifests push-only-amd64 push-only-arm64
	@echo "Creating multi-arch manifest for $(IMAGE_NAME)..."
	$(CONTAINER) manifest create $(IMAGE_NAME) $(IMAGE_NAME)-amd64 $(IMAGE_NAME)-arm64
	@echo "Pushing manifest..."
	$(CONTAINER) manifest push --all $(IMAGE_NAME) docker://$(IMAGE_NAME)
	@echo "Successfully pushed multi-arch manifest $(IMAGE_NAME)"


# Build for current architecture (PostgreSQL)
.PHONY: build-postgres
build-postgres:
	$(CONTAINER) build -f $(CONTAINERFILE_PG) -t $(LOCAL_IMAGE_NAME_PG) . --build-arg FRAPPE_BRANCH=$(FRAPPE_BRANCH) --build-arg TARGETARCH=$(shell uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')

# Build for AMD64 (PostgreSQL)
.PHONY: build-postgres-amd64
build-postgres-amd64:
	$(CONTAINER) build -f $(CONTAINERFILE_PG) --platform=linux/amd64 -t $(LOCAL_IMAGE_NAME_PG)-amd64 . --build-arg FRAPPE_BRANCH=$(FRAPPE_BRANCH) --build-arg TARGETARCH=amd64

# Build for ARM64 (PostgreSQL)
.PHONY: build-postgres-arm64
build-postgres-arm64:
	@echo "Building $(LOCAL_IMAGE_NAME_PG)-arm64 with FRAPPE_VERSION=$(FRAPPE_VERSION)"
	$(CONTAINER) build -f $(CONTAINERFILE_PG) --platform=linux/arm64 -t $(LOCAL_IMAGE_NAME_PG)-arm64 . --build-arg FRAPPE_BRANCH=$(FRAPPE_BRANCH) --build-arg TARGETARCH=arm64
	@echo "Build completed. Verifying image was created:"
	$(CONTAINER) images $(LOCAL_IMAGE_NAME_PG)-arm64

# Push Postgres targets
.PHONY: push-postgres push-postgres-only-amd64 push-postgres-only-arm64 push-postgres-manifest
push-postgres:
	$(CONTAINER) tag $(LOCAL_IMAGE_NAME_PG) $(IMAGE_NAME_PG)
	$(CONTAINER) push $(IMAGE_NAME_PG)

push-postgres-only-amd64:
	@echo "Tagging and pushing Postgres AMD64 image..."
	$(CONTAINER) tag $(LOCAL_IMAGE_NAME_PG)-amd64 $(IMAGE_NAME_PG)-amd64
	$(CONTAINER) push $(IMAGE_NAME_PG)-amd64
	@echo "Successfully pushed $(IMAGE_NAME_PG)-amd64"

push-postgres-only-arm64:
	@echo "Tagging and pushing Postgres ARM64 image..."
	$(CONTAINER) tag $(LOCAL_IMAGE_NAME_PG)-arm64 $(IMAGE_NAME_PG)-arm64
	$(CONTAINER) push $(IMAGE_NAME_PG)-arm64
	@echo "Successfully pushed $(IMAGE_NAME_PG)-arm64"

.PHONY: remove-postgres-manifests
remove-postgres-manifests:
	$(CONTAINER) manifest exists $(IMAGE_NAME_PG) && $(CONTAINER) manifest rm $(IMAGE_NAME_PG) || true
	$(CONTAINER) manifest exists $(IMAGE_NAME_PG)-$(IMAGE_TAG) && $(CONTAINER) manifest rm $(IMAGE_NAME_PG)-$(IMAGE_TAG) || true

push-postgres-manifest: remove-postgres-manifests push-postgres-only-amd64 push-postgres-only-arm64
	@echo "Creating multi-arch manifest for $(IMAGE_NAME_PG)..."
	$(CONTAINER) manifest create $(IMAGE_NAME_PG) $(IMAGE_NAME_PG)-amd64 $(IMAGE_NAME_PG)-arm64
	@echo "Pushing manifest..."
	$(CONTAINER) manifest push --all $(IMAGE_NAME_PG) docker://$(IMAGE_NAME_PG)
	@echo "Successfully pushed multi-arch manifest $(IMAGE_NAME_PG)"


# Frappe Runnable App builds
.PHONY: frappe-app frappe-app-amd64 frappe-app-arm64
frappe-app: build
	$(CONTAINER) build -f Containerfile.frappe -t $(LOCAL_FRAPPE_APP_IMAGE_NAME) . --build-arg BUILDER_IMAGE=$(LOCAL_IMAGE_NAME)

frappe-app-amd64: build-amd64
	$(CONTAINER) build -f Containerfile.frappe --platform=linux/amd64 -t $(LOCAL_FRAPPE_APP_IMAGE_NAME)-amd64 . --build-arg BUILDER_IMAGE=$(LOCAL_IMAGE_NAME)-amd64

frappe-app-arm64: build-arm64
	$(CONTAINER) build -f Containerfile.frappe --platform=linux/arm64 -t $(LOCAL_FRAPPE_APP_IMAGE_NAME)-arm64 . --build-arg BUILDER_IMAGE=$(LOCAL_IMAGE_NAME)-arm64

# Remove Frappe App manifests
.PHONY: remove-frappe-app-manifests
remove-frappe-app-manifests:
	$(CONTAINER) manifest exists $(FRAPPE_APP_IMAGE_NAME) && $(CONTAINER) manifest rm $(FRAPPE_APP_IMAGE_NAME) || true
	$(CONTAINER) manifest exists $(FRAPPE_APP_IMAGE_NAME)-$(IMAGE_TAG) && $(CONTAINER) manifest rm $(FRAPPE_APP_IMAGE_NAME)-$(IMAGE_TAG) || true

# Create and push Frappe App multi-arch manifest
.PHONY: frappe-app-manifest
frappe-app-manifest: remove-frappe-app-manifests push-frappe-app

# Push Frappe App images
.PHONY: push-frappe-app
push-frappe-app:
	@echo "Tagging and pushing Frappe App AMD64 image..."
	$(CONTAINER) tag $(LOCAL_FRAPPE_APP_IMAGE_NAME)-amd64 $(FRAPPE_APP_IMAGE_NAME)-amd64
	$(CONTAINER) push $(FRAPPE_APP_IMAGE_NAME)-amd64
	@echo "Tagging and pushing Frappe App ARM64 image..."
	$(CONTAINER) tag $(LOCAL_FRAPPE_APP_IMAGE_NAME)-arm64 $(FRAPPE_APP_IMAGE_NAME)-arm64
	$(CONTAINER) push $(FRAPPE_APP_IMAGE_NAME)-arm64
	@echo "Creating multi-arch manifest for $(FRAPPE_APP_IMAGE_NAME)..."
	$(CONTAINER) manifest create $(FRAPPE_APP_IMAGE_NAME) $(FRAPPE_APP_IMAGE_NAME)-amd64 $(FRAPPE_APP_IMAGE_NAME)-arm64
	@echo "Pushing manifest..."
	$(CONTAINER) manifest push --all $(FRAPPE_APP_IMAGE_NAME) docker://$(FRAPPE_APP_IMAGE_NAME)
	@echo "Successfully pushed multi-arch manifest $(FRAPPE_APP_IMAGE_NAME)"


# ERPNext builds
.PHONY: erpnext erpnext-amd64 erpnext-arm64
erpnext:
	./s2i-podman.sh test/erpnext $(LOCAL_ERP_IMAGE_NAME) $(LOCAL_IMAGE_NAME) --frappe-branch=$(FRAPPE_BRANCH)

erpnext-amd64: build-amd64
	./s2i-podman.sh --arch amd64 test/erpnext $(LOCAL_ERP_IMAGE_NAME)-amd64 $(LOCAL_IMAGE_NAME)-amd64 --frappe-branch=$(FRAPPE_BRANCH)

erpnext-arm64: build-arm64
	./s2i-podman.sh --arch arm64 test/erpnext $(LOCAL_ERP_IMAGE_NAME)-arm64 $(LOCAL_IMAGE_NAME)-arm64 --frappe-branch=$(FRAPPE_BRANCH)

# Remove ERPNext manifests
.PHONY: remove-erpnext-manifests
remove-erpnext-manifests:
	$(CONTAINER) manifest exists $(ERP_IMAGE_NAME) && $(CONTAINER) manifest rm $(ERP_IMAGE_NAME) || true
	$(CONTAINER) manifest exists $(ERP_IMAGE_NAME)-$(IMAGE_TAG) && $(CONTAINER) manifest rm $(ERP_IMAGE_NAME)-$(IMAGE_TAG) || true

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


# ERPNext PostgreSQL builds
.PHONY: erpnext-postgres erpnext-postgres-amd64 erpnext-postgres-arm64
erpnext-postgres:
	./s2i-podman.sh test/erpnext $(LOCAL_ERP_IMAGE_NAME_PG) $(LOCAL_IMAGE_NAME_PG) --frappe-branch=$(FRAPPE_BRANCH)

erpnext-postgres-amd64: build-postgres-amd64
	./s2i-podman.sh --arch amd64 test/erpnext $(LOCAL_ERP_IMAGE_NAME_PG)-amd64 $(LOCAL_IMAGE_NAME_PG)-amd64 --frappe-branch=$(FRAPPE_BRANCH)

erpnext-postgres-arm64: build-postgres-arm64
	./s2i-podman.sh --arch arm64 test/erpnext $(LOCAL_ERP_IMAGE_NAME_PG)-arm64 $(LOCAL_IMAGE_NAME_PG)-arm64 --frappe-branch=$(FRAPPE_BRANCH)

# Remove ERPNext PostgreSQL manifests
.PHONY: remove-erpnext-postgres-manifests
remove-erpnext-postgres-manifests:
	$(CONTAINER) manifest exists $(ERP_IMAGE_NAME_PG) && $(CONTAINER) manifest rm $(ERP_IMAGE_NAME_PG) || true
	$(CONTAINER) manifest exists $(ERP_IMAGE_NAME_PG)-$(IMAGE_TAG) && $(CONTAINER) manifest rm $(ERP_IMAGE_NAME_PG)-$(IMAGE_TAG) || true

# Create and push ERPNext PostgreSQL multi-arch manifest
.PHONY: erpnext-postgres-manifest
erpnext-postgres-manifest: remove-erpnext-postgres-manifests push-erpnext-postgres

# Push ERPNext PostgreSQL images
.PHONY: push-erpnext-postgres
push-erpnext-postgres:
	@echo "Tagging and pushing ERPNext PostgreSQL AMD64 image..."
	$(CONTAINER) tag $(LOCAL_ERP_IMAGE_NAME_PG)-amd64 $(ERP_IMAGE_NAME_PG)-amd64
	$(CONTAINER) push $(ERP_IMAGE_NAME_PG)-amd64
	@echo "Successfully pushed $(ERP_IMAGE_NAME_PG)-amd64"
	
	@echo "Tagging and pushing ERPNext PostgreSQL ARM64 image..."
	$(CONTAINER) tag $(LOCAL_ERP_IMAGE_NAME_PG)-arm64 $(ERP_IMAGE_NAME_PG)-arm64
	$(CONTAINER) push $(ERP_IMAGE_NAME_PG)-arm64
	@echo "Successfully pushed $(ERP_IMAGE_NAME_PG)-arm64"

	@echo "Creating multi-arch manifest for $(ERP_IMAGE_NAME_PG)..."
	$(CONTAINER) manifest create $(ERP_IMAGE_NAME_PG) $(ERP_IMAGE_NAME_PG)-amd64 $(ERP_IMAGE_NAME_PG)-arm64
	@echo "Pushing manifest..."
	$(CONTAINER) manifest push --all $(ERP_IMAGE_NAME_PG) docker://$(ERP_IMAGE_NAME_PG)
	@echo "Successfully pushed multi-arch manifest $(ERP_IMAGE_NAME_PG)"

# Clean up images and manifests
.PHONY: clean clean-manifests
clean:
	$(CONTAINER) rmi -f $(LOCAL_IMAGE_NAME) $(LOCAL_IMAGE_NAME)-amd64 $(LOCAL_IMAGE_NAME)-arm64 || true
	$(CONTAINER) rmi -f $(LOCAL_IMAGE_NAME_PG) $(LOCAL_IMAGE_NAME_PG)-amd64 $(LOCAL_IMAGE_NAME_PG)-arm64 || true
	$(CONTAINER) rmi -f $(LOCAL_FRAPPE_APP_IMAGE_NAME) $(LOCAL_FRAPPE_APP_IMAGE_NAME)-amd64 $(LOCAL_FRAPPE_APP_IMAGE_NAME)-arm64 || true
	$(CONTAINER) rmi -f $(LOCAL_ERP_IMAGE_NAME) $(LOCAL_ERP_IMAGE_NAME)-amd64 $(LOCAL_ERP_IMAGE_NAME)-arm64 || true
	$(CONTAINER) rmi -f $(LOCAL_ERP_IMAGE_NAME_PG) $(LOCAL_ERP_IMAGE_NAME_PG)-amd64 $(LOCAL_ERP_IMAGE_NAME_PG)-arm64 || true
	$(CONTAINER) rmi -f $(IMAGE_NAME) $(IMAGE_NAME)-amd64 $(IMAGE_NAME)-arm64 || true
	$(CONTAINER) rmi -f $(IMAGE_NAME_PG) $(IMAGE_NAME_PG)-amd64 $(IMAGE_NAME_PG)-arm64 || true
	$(CONTAINER) rmi -f $(FRAPPE_APP_IMAGE_NAME) $(FRAPPE_APP_IMAGE_NAME)-amd64 $(FRAPPE_APP_IMAGE_NAME)-arm64 || true
	$(CONTAINER) rmi -f $(ERP_IMAGE_NAME) $(ERP_IMAGE_NAME)-amd64 $(ERP_IMAGE_NAME)-arm64 || true
	$(CONTAINER) rmi -f $(ERP_IMAGE_NAME_PG) $(ERP_IMAGE_NAME_PG)-amd64 $(ERP_IMAGE_NAME_PG)-arm64 || true

clean-manifests: remove-manifests remove-frappe-app-manifests remove-erpnext-manifests remove-postgres-manifests remove-erpnext-postgres-manifests

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
