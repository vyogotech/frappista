# syntax=docker/dockerfile:1
# check=skip=InvalidBaseImagePlatform
ARG TARGETARCH=amd64

# Stage 0: Build Redis
FROM almalinux:9 AS redis-builder
ARG TARGETARCH
ENV REDIS_SOURCE_VERSION=7.2.7
RUN --mount=type=cache,target=/var/cache/dnf \
    dnf install -y --allowerasing make gcc tar curl && \
    mkdir -p /tmp/redis-build && \
    curl -fsSL "https://download.redis.io/releases/redis-${REDIS_SOURCE_VERSION}.tar.gz" | tar xzf - -C /tmp/redis-build --strip-components=1 && \
    cd /tmp/redis-build && \
    make MALLOC=libc CFLAGS="-fno-lto" -j$(nproc) && \
    make install PREFIX=/usr/local

# Stage 1: Base image with tools and dependencies
# Using almalinux:9 as base for true multi-arch support (amd64 and arm64) without UBI subscription limits
FROM almalinux:9 AS builder
USER root
ARG TARGETARCH

ENV APP_ROOT=/opt/app-root \
    MYSQL_UID=27 \
    FRAPPE_UID=1001

# Set labels
LABEL maintainer="Dev <dev@vyogolabs.tech>"
LABEL io.k8s.description="Single Node Environment for ERPNext" \
     io.k8s.display-name="Frappe Single node env for Devs" \
     io.openshift.expose-services="8080:http" \
     io.openshift.tags="ERPNext,Single Node" \
     io.openshift.s2i.scripts-url=image:///usr/libexec/s2i \
     maintainer="vyogolabs.tech <dev@vyogolabs.tech>"

# Install base dependencies
RUN --mount=type=cache,target=/var/cache/dnf \
    dnf -y module enable mariadb:10.11 && \
    dnf install -y mariadb mariadb-server mariadb-server-utils mariadb-devel && \
    mkdir -p /var/lib/mysql && \
    mkdir -p /var/run/mariadb && \
    chown -R ${MYSQL_UID}:${MYSQL_UID} /var/lib/mysql /var/run/mariadb && \
    chmod 755 /var/lib/mysql /var/run/mariadb && \
    useradd -u ${FRAPPE_UID} -r -g 0 -d /home/frappe -s /sbin/nologin -c "Default Application User" default && \
    mkdir -p /home/frappe && \
    chown ${FRAPPE_UID}:0 /home/frappe && \
    dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm \
    wget \
    vim \
    git \
    gcc \
    libffi-devel \
    libxml2-devel \
    libxslt-devel \
    openssl-devel \
    bzip2-devel \
    zlib-devel \
    ncurses-devel \
    xz-devel \
    libuuid-devel \
    file \
    procps-ng \
    mariadb-connector-c-devel && \
    rm -rf /mnt/rootfs/var/cache/* /mnt/rootfs/var/log/dnf* /mnt/rootfs/var/log/dnf.*

# Install wkhtmltopdf based on architecture
RUN --mount=type=cache,target=/var/cache/dnf \
    ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then \
        #install jq for x86_64 \
        dnf -y install jq && \
        dnf -y install https://rpmfind.net/linux/almalinux/9/AppStream/x86_64/os/Packages/xorg-x11-fonts-75dpi-7.5-33.el9.noarch.rpm && \
        dnf -y install https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox-0.12.6.1-3.almalinux9.x86_64.rpm; \
    elif [ "$ARCH" = "aarch64" ]; then \
        dnf -y install jq && \
        dnf -y install https://rpmfind.net/linux/almalinux/9/AppStream/aarch64/os/Packages/xorg-x11-fonts-75dpi-7.5-33.el9.noarch.rpm && \
        dnf -y install https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox-0.12.6.1-3.almalinux9.aarch64.rpm; \
    else \
        echo "Unsupported architecture: $ARCH" && exit 1; \
    fi && \
    dnf clean all

# Setup Redis — copy from cached builder stage
ENV REDIS_VERSION=7 \
    HOME=/var/lib/redis
RUN getent group redis &> /dev/null || groupadd -r redis &> /dev/null && \
    usermod -l redis -aG redis -c 'Redis Server' default &> /dev/null

COPY --from=redis-builder /usr/local/bin/redis-server /usr/bin/redis-server
COPY --from=redis-builder /usr/local/bin/redis-cli /usr/bin/redis-cli

RUN redis-server --version | grep -qe "^Redis server v=$REDIS_VERSION\." && echo "Found VERSION $REDIS_VERSION" && \
    mkdir -p /var/lib/redis/data && chown -R redis.0 /var/lib/redis && \
    [[ "$(id redis)" == "uid=1001(redis)"* ]] && usermod -l frappe -u 1001 -d /home/frappe -m -c "Frappe Bench" redis

# Setup Python
ENV PYTHON_VERSION=3.14 \
    PATH=$HOME/.local/bin/:$PATH \
    PYTHONUNBUFFERED=1 \
    PYTHONIOENCODING=UTF-8 \
    LC_ALL=C.UTF-8 \
    LANG=C.UTF-8 \
    CNB_STACK_ID=com.redhat.stacks.ubi9-python-311 \
    CNB_USER_ID=1001 \
    CNB_GROUP_ID=0 \
    PIP_NO_CACHE_DIR=off

RUN --mount=type=cache,target=/var/cache/dnf \
    INSTALL_PKGS="python3.14 python3.14-devel python3.14-pip" && \
    dnf -y --setopt=tsflags=nodocs install $INSTALL_PKGS && \
    rpm -V $INSTALL_PKGS && \
    alternatives --install /usr/bin/python python /usr/bin/python3.14 1 && \
    alternatives --set python /usr/bin/python3.14 && \
    ln -sf /usr/bin/python3.14 /usr/bin/python3 && \
    ln -sf /usr/bin/python3.14 /usr/bin/python3-config && \
    python3.14 -m pip install --no-cache-dir --upgrade pip && \
    dnf -y clean all --enablerepo='*'

# Setup Node.js and Yarn
ENV NPM_RUN=start \
    PLATFORM="el9" \
    NODEJS_VERSION=24 \
    NAME=nodejs \
    NVM_DIR=/usr/local/nvm \
    ESBUILD_VERSION=0.16.17 \
    NPM_CONFIG_PREFIX=$HOME/.npm-global \
    PATH=$HOME/node_modules/.bin/:$HOME/.npm-global/bin/:$PATH

RUN --mount=type=cache,target=/var/cache/dnf \
    INSTALL_PKGS="nodejs nodejs-nodemon nodejs-full-i18n npm findutils tar which" && \
    dnf -y module disable nodejs && \
    dnf -y module enable nodejs:$NODEJS_VERSION && \
    dnf -y --nodocs --setopt=install_weak_deps=0 install $INSTALL_PKGS && \
    node -v | grep -qe "^v$NODEJS_VERSION\." && echo "Found VERSION $NODEJS_VERSION" && \
    npm install -g --no-audit --no-fund --loglevel=error yarn && \
    dnf clean all && \
    rm -rf /mnt/rootfs/var/cache/* /mnt/rootfs/var/log/dnf* /mnt/rootfs/var/log/dnf.*

# Setup Nginx
ENV NAME=nginx \
    NGINX_VERSION=1.22 \
    NGINX_SHORT_VER=122 \
    VERSION=0 \
    NGINX_CONFIGURATION_PATH=${APP_ROOT}/etc/nginx.d \
    NGINX_CONF_PATH=/etc/nginx/nginx.conf \
    NGINX_DEFAULT_CONF_PATH=${APP_ROOT}/etc/nginx.default.d \
    NGINX_CONTAINER_SCRIPTS_PATH=/usr/share/container-scripts/nginx \
    NGINX_APP_ROOT=${APP_ROOT} \
    NGINX_LOG_PATH=/var/log/nginx \
    NGINX_PERL_MODULE_PATH=${APP_ROOT}/etc/perl

RUN --mount=type=cache,target=/var/cache/dnf \
    dnf -y module enable nginx:$NGINX_VERSION && \
    INSTALL_PKGS="nginx" && \
    dnf install -y --setopt=tsflags=nodocs $INSTALL_PKGS && \
    rpm -V $INSTALL_PKGS && \
    nginx -v 2>&1 | grep -qe "nginx/$NGINX_VERSION\." && echo "Found VERSION $NGINX_VERSION" && \
    sed -i 's/listen       80;/listen       8080;/' /etc/nginx/nginx.conf && \
    sed -i 's/listen       \[::\]:80;/listen       \[::\]:8080;/' /etc/nginx/nginx.conf && \
    sed -i 's/user  nginx;/user frappe/g' /etc/nginx/nginx.conf && \
    dnf -y clean all --enablerepo='*' && \
    mkdir -p ${NGINX_APP_ROOT}/etc/nginx.d/ && \
    mkdir -p ${NGINX_APP_ROOT}/etc/nginx.default.d/ && \
    mkdir -p ${NGINX_APP_ROOT}/src/nginx-start/ && \
    mkdir -p ${NGINX_CONTAINER_SCRIPTS_PATH}/nginx-start && \
    mkdir -p ${NGINX_LOG_PATH} && \
    mkdir -p ${NGINX_PERL_MODULE_PATH} && \
    chown -R 1001:0 ${NGINX_CONF_PATH} && \
    chown -R 1001:0 ${NGINX_APP_ROOT}/etc && \
    chown -R 1001:0 ${NGINX_APP_ROOT}/src/nginx-start/ && \
    chown -R 1001:0 ${NGINX_CONTAINER_SCRIPTS_PATH}/nginx-start && \
    chown -R 1001:0 /var/lib/nginx /var/log/nginx /run && \
    chmod    ug+rw  ${NGINX_CONF_PATH} && \
    chmod -R ug+rwX ${NGINX_APP_ROOT}/etc && \
    chmod -R ug+rwX ${NGINX_APP_ROOT}/src/nginx-start/ && \
    chmod -R ug+rwX ${NGINX_CONTAINER_SCRIPTS_PATH}/nginx-start && \
    chmod -R ug+rwX /var/lib/nginx /var/log/nginx /run && \
    chown -R 1001:0 /var && \
    chmod -R ug+rwX /var && touch /help.1

# Stage 2: S2I scripts and Frappe setup
FROM builder AS final
USER root
ARG TARGETARCH

# Set the environment variable for MySQL
ENV MYSQL_ROOT_PASSWORD=ChangeMe

# Handle S2I scripts
RUN if [ -f /usr/libexec/s2i/assemble ]; then mv /usr/libexec/s2i/assemble /usr/libexec/s2i/assemble.original; fi && \
    if [ -f /usr/libexec/s2i/run ]; then mv /usr/libexec/s2i/run /usr/libexec/s2i/run.original; fi

# Copy and setup S2I scripts
COPY --chown=1001:0 ./s2i/bin/* /usr/libexec/s2i/
RUN chmod +x /usr/libexec/s2i/* && \
    chown 1001:0 /usr/libexec/s2i/*

# Switch to frappe user for application setup
USER frappe

# Install Frappe bench and dependencies
# frappe-bench >= 5.22 hard-codes `uv venv` during `bench init`.
# Pin to the last pre-uv bench series so the image follows the standard
# Python virtualenv flow instead of requiring an emulation-sensitive Rust binary.
RUN --mount=type=cache,id=pip-final-${TARGETARCH},target=/home/frappe/.cache/pip,uid=1001,gid=0 \
    pip install "click<8.2" "frappe-bench==5.21.5" \
    && pip install redis \
    && pip install mysql-connector-python

# Setup Frappe
WORKDIR /home/frappe
ARG FRAPPE_BRANCH=develop
ARG FRAPPE_PATH=https://github.com/frappe/frappe

RUN --mount=type=cache,id=pip-${FRAPPE_BRANCH}-${TARGETARCH},target=/home/frappe/.cache/pip,uid=1001,gid=0 \
  --mount=type=cache,id=npm-${FRAPPE_BRANCH}-${TARGETARCH},target=/home/frappe/.npm,uid=1001,gid=0 \
  echo "using version ${FRAPPE_BRANCH}" && bench init \
  --frappe-branch=${FRAPPE_BRANCH} \
  --frappe-path=${FRAPPE_PATH} \
  --no-backups \
  --skip-redis-config-generation \
  /home/frappe/frappe-bench && \
  cd /home/frappe/frappe-bench && \
  find apps -mindepth 1 -path "*/.git" | xargs rm -fr && \
  chown -R 1001:0 . && chmod -R ug+rwX . && \
  bench set-config --global redis_cache "redis://localhost:6379" && \
  bench set-config --global redis_queue "redis://localhost:6379" && \
  bench set-config --global redis_socketio "redis://localhost:6379"

# Expose ports
EXPOSE 8000

# Set final workdir
WORKDIR /home/frappe/frappe-bench

# Set entrypoint
CMD ["/usr/libexec/s2i/usage"]