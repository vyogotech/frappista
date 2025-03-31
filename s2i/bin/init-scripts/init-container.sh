#!/bin/bash
# -----------------------------------------------------------------------------
# Frappe Site Setup Script
# -----------------------------------------------------------------------------
# This script is used to initialize and set up a Frappe site.
#
# Copyright (C) 2025 Vyogo Technologies Pvt Ltd
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
# -----------------------------------------------------------------------------

set -e
source utils.sh

# Path to track initialization
INIT_FLAG="/var/lib/mysql/.container-initialized"

# Function to ensure machine ID is set
ensure_machine_id() {
    if [ ! -s /etc/machine-id ]; then
        log "Machine ID is missing. Setting up machine ID."
        systemd-machine-id-setup
        log "Machine ID setup completed."
    else
        log "Machine ID already exists."
    fi
}

# Function to start MariaDB service
start_mariadb() {
    log "Starting MariaDB service."
    systemctl start mariadb
    log "MariaDB service started."
}

# Function to wait for MariaDB to be ready
wait_for_mariadb() {
    log "Waiting for MariaDB to be ready..."
    until mysqladmin ping &>/dev/null; do
        log "MariaDB is not ready yet. Retrying in 2 seconds..."
        sleep 2
    done
    log "MariaDB is ready."
}

# Function to run secure installation
run_secure_installation() {
    log "Running mysql_secure_installation."
    if command -v mysql_secure_installation &>/dev/null; then
        log "mysql_secure_installation found. Running it."
        mysql_secure_installation << EOF
y
ChangeMe
ChangeMe
y
y
y
y
EOF
    elif command -v mariadb-secure-installation &>/dev/null; then
        log "mariadb-secure-installation found. Running it."
        mariadb-secure-installation << EOF
y
ChangeMe
ChangeMe
y
y
y
y
EOF
    else
        log "Neither mysql_secure_installation nor mariadb-secure-installation found. Exiting."
        exit 1
    fi
    log "mysql_secure_installation completed."
}

# Function to create initialization flag
create_init_flag() {
    log "Creating initialization flag at $INIT_FLAG."
    touch "$INIT_FLAG"
    log "Initialization flag created."
}

# Function to set up Frappe site
setup_frappe_site() {
    log "Creating default site and installing apps."
    source frappe-site-setup.sh
    if [ $? -eq 0 ]; then
        log "Frappe site setup completed successfully."
    else
        log "Frappe site setup failed. Exiting."
        exit 1
    fi
}

# Function to stop MariaDB service
stop_mariadb() {
    log "Stopping MariaDB service."
    systemctl stop mariadb
    log "MariaDB service stopped."
}

# Main script execution
main() {
    ensure_machine_id

    # Check if initialization has already been done
    if [ ! -f "$INIT_FLAG" ]; then
        log "Initialization flag not found. Performing first-time container initialization."

        start_mariadb
        wait_for_mariadb
        run_secure_installation
        create_init_flag
        setup_frappe_site
        stop_mariadb
    else
        log "Initialization flag found. Skipping first-time initialization."
    fi

    # Execute the original CMD (systemd init)
    log "Executing the original CMD: /usr/sbin/init."
    exec /usr/sbin/init
}

# Run the main function
main