IMAGE_NAME = vyogotech/frappe:s2i-base
.PHONY: build
build:
	podman build -t $(IMAGE_NAME) .

.PHONY: build-frappe-base
# Hack to build the base image faster with new layers. used for testing
increment:
	podman build -t $(IMAGE_NAME) -f Containerfile.override .

.PHONY: test
test-erpnext:
	podman build -t $(IMAGE_NAME)-epnext .
	s2i-podman.sh test/erpnext vyogotech/erpnext:sne-latest vyogotech/frappe:s2i-base
	podman run -it --rm -v $(PWD)/test/erpnext:/tmp/test-erpnext $(IMAGE_NAME)-epnext /bin/bash -c "cd /tmp/test-erpnext && ./test.sh"
