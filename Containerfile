# Stage 1: Base image with tools and dependencies
FROM quay.io/sclorg/mariadb-1011-c9s AS builder
USER root

# Set labels
LABEL maintainer="Dev <dev@vyogolabs.tech>"
LABEL io.k8s.description="Single Node Environment for ERPNext" \
    io.k8s.display-name="Frappe Single node env for Devs" \
    io.openshift.expose-services="8080:http" \
    io.openshift.tags="ERPNext,Single Node" \
    io.openshift.s2i.scripts-url=image:///usr/libexec/s2i \
    maintainer="vyogolabs.tech <dev@vyogolabs.tech>"

# Install base dependencies
RUN dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm \
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
    mariadb-connector-c-devel && \
    rm -rf /mnt/rootfs/var/cache/* /mnt/rootfs/var/log/dnf* /mnt/rootfs/var/log/dnf.*

# Install wkhtmltopdf based on architecture
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then \
    #install jq for x86_64
    dnf -y install jq && \
    dnf -y install https://rpmfind.net/linux/almalinux/9/AppStream/x86_64/os/Packages/xorg-x11-fonts-75dpi-7.5-33.el9.noarch.rpm && \
    dnf -y install https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox-0.12.6.1-3.almalinux9.x86_64.rpm; \
    elif [ "$ARCH" = "aarch64" ]; then \
    dnf -y install jq.aarch64 && \
    dnf -y install https://rpmfind.net/linux/almalinux/9/AppStream/aarch64/os/Packages/xorg-x11-fonts-75dpi-7.5-33.el9.noarch.rpm && \
    dnf -y install https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox-0.12.6.1-3.almalinux9.aarch64.rpm; \
    else \
    echo "Unsupported architecture: $ARCH" && exit 1; \
    fi && \
    dnf clean all

# Setup Redis — compile from source with MALLOC=libc to avoid jemalloc segfaults
# under QEMU emulation (e.g. running amd64 images on Apple Silicon Macs).
ENV REDIS_VERSION=7 \
    REDIS_SOURCE_VERSION=7.2.7 \
    HOME=/var/lib/redis
RUN getent group redis &> /dev/null || groupadd -r redis &> /dev/null && \
    usermod -l redis -aG redis -c 'Redis Server' default &> /dev/null && \
    dnf -y install policycoreutils make gcc && \
    cd /tmp && \
    curl -fsSL "https://download.redis.io/releases/redis-${REDIS_SOURCE_VERSION}.tar.gz" \
    -o redis.tar.gz && \
    tar xzf redis.tar.gz && \
    cd "redis-${REDIS_SOURCE_VERSION}" && \
    make MALLOC=libc CFLAGS="-fno-lto" -j1 && \
    make install PREFIX=/usr && \
    cd / && rm -rf /tmp/redis* && \
    dnf -y clean all --enablerepo='*' && \
    redis-server --version | grep -qe "^Redis server v=$REDIS_VERSION\." && echo "Found VERSION $REDIS_VERSION" && \
    mkdir -p /var/lib/redis/data && chown -R redis.0 /var/lib/redis && \
    [[ "$(id redis)" == "uid=1001(redis)"* ]] && usermod -l frappe -u 1001 -d /home/frappe -m -c "Frappe Bench" redis

# Setup Python
ENV PYTHON_VERSION=3.14 \
    PATH=$HOME/.local/bin/:$PATH \
    PYTHONUNBUFFERED=1 \
    PYTHONIOENCODING=UTF-8 \
    LC_ALL=en_US.UTF-8 \
    LANG=en_US.UTF-8 \
    CNB_STACK_ID=com.redhat.stacks.ubi9-python-311 \
    CNB_USER_ID=1001 \
    CNB_GROUP_ID=0 \
    PIP_NO_CACHE_DIR=off

RUN INSTALL_PKGS="python3.14 python3.14-devel python3.14-pip" && \
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

RUN INSTALL_PKGS="nodejs nodejs-nodemon nodejs-full-i18n npm findutils tar which" && \
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
    NGINX_DEFAULT_CONF_PATH=${NGINX_APP_ROOT}/etc/nginx.default.d \
    NGINX_CONTAINER_SCRIPTS_PATH=/usr/share/container-scripts/nginx \
    NGINX_APP_ROOT=${APP_ROOT} \
    NGINX_LOG_PATH=/var/log/nginx \
    NGINX_PERL_MODULE_PATH=${APP_ROOT}/etc/perl

RUN dnf -y module enable nginx:$NGINX_VERSION && \
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
    rpm-file-permissions && \
    chown -R 1001:0 /var && \
    chmod -R ug+rwX /var && touch /help.1

# Stage 2: S2I scripts and Frappe setup
FROM builder AS final
USER root

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
RUN pip install "click<8.2" "frappe-bench==5.21.5" \
    && pip install redis \
    && pip install mysql-connector-python

# Setup Frappe
WORKDIR /home/frappe
ARG FRAPPE_BRANCH=version-16
ARG FRAPPE_PATH=https://github.com/frappe/frappe

RUN echo "using version ${FRAPPE_BRANCH}" && bench init \
    --frappe-branch=${FRAPPE_BRANCH} \
    --frappe-path=${FRAPPE_PATH} \
    --no-backups \
    --skip-redis-config-generation \
    --verbose \
    /home/frappe/frappe-bench && \
    cd /home/frappe/frappe-bench && \
    find apps -mindepth 1 -path "*/.git" | xargs rm -fr && \
    chown -R 1001:0 . && chmod -R ug+rwX . && \
    bench set-config --global redis_cache "redis://localhost:6379" && \
    bench set-config --global redis_queue "redis://localhost:6379" && \
    bench set-config --global redis_socketio "redis://localhost:6379"

# The base image is linux/amd64-only, so RUN steps always execute as amd64
# (even when building with --platform linux/arm64). bench init therefore
# installs only @esbuild/linux-x64. Force-install the arm64 optional package
# too so bench build works on real aarch64 hosts (Apple Silicon, ARM servers).
RUN cd /home/frappe/frappe-bench/apps/frappe && \
    yarn add --dev --ignore-engines --silent \
        "@esbuild/linux-arm64@${ESBUILD_VERSION}" && \
    chown -R 1001:0 node_modules && chmod -R ug+rwX node_modules

# Expose ports
EXPOSE 8000

# Set final workdir
WORKDIR /home/frappe/frappe-bench

# Set entrypoint
CMD ["/usr/libexec/s2i/usage"]