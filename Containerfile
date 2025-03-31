FROM registry.redhat.io/rhel9/mariadb-1011
USER root

# TODO: Put the maintainer name in the image metadata
LABEL maintainer="Dev <dev@vyogolabs.tech>"

# TODO: Rename the builder environment variable to inform users about application you provide them
ENV MYSQL_ROOT_PASSWORD=ChangeMe
# TODO: Set labels used in OpenShift to describe the builder image
LABEL io.k8s.description="Single Node Environment for ERPNext" \
     io.k8s.display-name="Frappe Single node env for Devs" \
     io.openshift.expose-services="8080:http" \
     io.openshift.tags="ERPNext,Single Node" \
     io.openshift.s2i.scripts-url=image:///usr/libexec/s2i \
     maintainer="vyogolabs.tech <dev@vyogolabs.tech>"

     #----------START OTHER DEPENDENCIES----------------

RUN dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm  \
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
mariadb-connector-c-devel \
jq.aarch64 && \
rm -rf /mnt/rootfs/var/cache/* /mnt/rootfs/var/log/dnf* /mnt/rootfs/var/log/dnf.*

RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then \
        dnf -y install https://rpmfind.net/linux/almalinux/9/AppStream/x86_64/os/Packages/xorg-x11-fonts-75dpi-7.5-33.el9.noarch.rpm && \
        dnf -y install https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox-0.12.6.1-3.almalinux9.x86_64.rpm; \
    elif [ "$ARCH" = "aarch64" ]; then \
        dnf -y install https://rpmfind.net/linux/almalinux/9/AppStream/aarch64/os/Packages/xorg-x11-fonts-75dpi-7.5-33.el9.noarch.rpm && \
        dnf -y install https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox-0.12.6.1-3.almalinux9.aarch64.rpm; \
    else \
        echo "Unsupported architecture: $ARCH" && exit 1; \
    fi && \
    dnf clean all
#We need to see if this is needed
#RUN dnf -y install https://rpmfind.net/linux/almalinux/9.4/AppStream/ppc64le/os/Packages/xorg-x11-fonts-75dpi-7.5-33.el9.noarch.rpm 

#----------END OTHER DEPENDENCIES----------------

#We need to install redis,python , nodejs , yarn, npm and other dependencies
#----------START REDIS----------------
ENV REDIS_VERSION=7 \
    HOME=/var/lib/redis
RUN getent group  redis &> /dev/null || groupadd -r redis &> /dev/null && \
    usermod -l redis -aG redis -c 'Redis Server' default &> /dev/null && \
# Install gettext for envsubst command
    dnf -y module enable redis:$REDIS_VERSION && \
    INSTALL_PKGS="policycoreutils redis" && \
    dnf install -y --setopt=tsflags=nodocs $INSTALL_PKGS && \
    rpm -V $INSTALL_PKGS && \
    dnf -y clean all --enablerepo='*' && \
    redis-server --version | grep -qe "^Redis server v=$REDIS_VERSION\." && echo "Found VERSION $REDIS_VERSION" && \
    mkdir -p /var/lib/redis/data && chown -R redis.0 /var/lib/redis && \
    [[ "$(id redis)" == "uid=1001(redis)"* ]] && usermod -l frappe -u 1001 -d /home/frappe -m -c "Frappe Bench" redis 

#------------END REDIS---------------

#----------START PYTHON----------------

ENV PYTHON_VERSION=3.11 \
    PATH=$HOME/.local/bin/:$PATH \
    PYTHONUNBUFFERED=1 \
    PYTHONIOENCODING=UTF-8 \
    LC_ALL=en_US.UTF-8 \
    LANG=en_US.UTF-8 \
    CNB_STACK_ID=com.redhat.stacks.ubi9-python-311 \
    CNB_USER_ID=1001 \
    CNB_GROUP_ID=0 \
    PIP_NO_CACHE_DIR=off

RUN INSTALL_PKGS="python3.11 python3.11-devel python3.11-pip" && \
    dnf -y --setopt=tsflags=nodocs install $INSTALL_PKGS && \
    rpm -V $INSTALL_PKGS && \
    #make 3.11 the default python
    alternatives --install /usr/bin/python python /usr/bin/python3.11 1 && \
    alternatives --set python /usr/bin/python3.11 && \
    #update symlinks
    ln -sf /usr/bin/python3.11 /usr/bin/python3 && \
    ln -sf /usr/bin/python3.11 /usr/bin/python3-config && \
    # Install pipenv
    python3.11 -m pip install --no-cache-dir --upgrade pip && \
    dnf -y clean all --enablerepo='*'

#---------- END PYTHON----------------
#----------START NODEJS & YARN----------------
ENV NPM_RUN=start \
    PLATFORM="el9" \
    NODEJS_VERSION=18 \
    NPM_RUN=start \
    NAME=nodejs \
    NVM_DIR=/usr/local/nvm \
    NPM_CONFIG_PREFIX=$HOME/.npm-global \
    PATH=$HOME/node_modules/.bin/:$HOME/.npm-global/bin/:$PATH

RUN INSTALL_PKGS="nodejs nodejs-nodemon nodejs-full-i18n npm findutils tar which" && \
    dnf -y module disable nodejs && \
    dnf -y module enable nodejs:$NODEJS_VERSION && \
    dnf -y --nodocs --setopt=install_weak_deps=0 install $INSTALL_PKGS && \
    node -v | grep -qe "^v$NODEJS_VERSION\." && echo "Found VERSION $NODEJS_VERSION" && \
    #install yarn
    npm install -g --no-audit --no-fund --loglevel=error yarn && \
    dnf clean all && \
    rm -rf /mnt/rootfs/var/cache/* /mnt/rootfs/var/log/dnf* /mnt/rootfs/var/log/dnf.*

#----------END NODEJS & YARN----------------

#-------- START NGINX-----------
ENV NAME=nginx \
    NGINX_VERSION=1.22 \
    NGINX_SHORT_VER=122 \
    VERSION=0

    # Install Nginx

ENV NGINX_CONFIGURATION_PATH=${APP_ROOT}/etc/nginx.d \
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
    #use sed to change listen port to 8080
    sed -i 's/listen       80;/listen       8080;/' /etc/nginx/nginx.conf && \
    #listen       [::]:80
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
    chown -R 1001:0 ${NGINX_APP_ROOT}/src/nginx-start/  && \
    chown -R 1001:0 ${NGINX_CONTAINER_SCRIPTS_PATH}/nginx-start && \
    chown -R 1001:0 /var/lib/nginx /var/log/nginx /run && \
    chmod    ug+rw  ${NGINX_CONF_PATH} && \
    chmod -R ug+rwX ${NGINX_APP_ROOT}/etc && \
    chmod -R ug+rwX ${NGINX_APP_ROOT}/src/nginx-start/  && \
    chmod -R ug+rwX ${NGINX_CONTAINER_SCRIPTS_PATH}/nginx-start && \
    chmod -R ug+rwX /var/lib/nginx /var/log/nginx /run && \
    rpm-file-permissions && \
    chown -R 1001:0 /var && \
    chmod -R ug+rwX /var
    

#-------- END NGINX-----------

# TODO: Drop the root user and make the content of /opt/app-root owned by user 1001
# RUN chown -R 1001:1001 /opt/app-root
USER frappe
# This default user is created in the openshift/base-centos7 image
RUN  pip install frappe-bench \
     && pip install redis \
     && pip install mysql-connector-python

WORKDIR /home/frappe
ARG FRAPPE_BRANCH=version-15
ARG FRAPPE_PATH=https://github.com/frappe/frappe
# ARG ERPNEXT_REPO=https://github.com/frappe/erpnext
# ARG ERPNEXT_BRANCH=version-15
RUN  bench init \
  --frappe-branch=${FRAPPE_BRANCH} \
  --frappe-path=${FRAPPE_PATH} \
  --no-backups \
  --skip-redis-config-generation \
  --verbose \
  /home/frappe/frappe-bench && \
  cd /home/frappe/frappe-bench && \
#   bench get-app --branch=${ERPNEXT_BRANCH} --resolve-deps erpnext ${ERPNEXT_REPO} && \
  find apps -mindepth 1 -path "*/.git" | xargs rm -fr


# Expose necessary portsss
EXPOSE 8000 3306 6379
WORKDIR /home/frappe/frappe-bench
USER 1001
CMD ["/usr/libexec/s2i/usage"]