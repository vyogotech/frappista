REGISTRY=docker.io
REPO=$(REGISTRY)/vyogo
IMAGE_NAME =$(REPO)/frappe:s2i-base

.PHONY: build
build:
	podman build -t $(IMAGE_NAME) .

.PHONY: increment push

build-push:
	podman build -t $(IMAGE_NAME) .
	podman push $(IMAGE_NAME)
	
push:
	podman push $(IMAGE_NAME)

# Hack to build the base image faster with new layers. used for testing
increment:
	podman build -t $(IMAGE_NAME) -f Containerfile.override . --no-cache

.PHONY: erpnext
erpnext:
	./s2i-podman.sh test/erpnext vyogo/erpnext:sne-latest  $(IMAGE_NAME)