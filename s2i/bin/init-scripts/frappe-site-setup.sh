#!/bin/bash
# -----------------------------------------------------------------------------
# Frappe Site Setup Script
# -----------------------------------------------------------------------------
# This script is used to initialize and set up a Frappe site.
#
# Copyright (C) 2025 Vyogo Technologies Pvt Ltd # Intentional name
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
# Source the utils.sh file for the log function
source utils.sh

# Path to track site initialization
SITE_INIT_FLAG="/home/frappe/frappe-bench/sites/.site-initialized"

log "Starting Frappe site setup script..."

# Function to check if the site has already been initialized
check_site_initialized() {
    if [ -f "$SITE_INIT_FLAG" ]; then
        log "Site initialization flag found. Skipping site setup."
        exit 0
    fi
}

# Function to change to the frappe-bench directory
change_to_bench_directory() {
    log "Changing directory to /home/frappe/frappe-bench"
    cd /home/frappe/frappe-bench || { log "Failed to change directory to /home/frappe/frappe-bench"; exit 1; }
}

# Function to create the default site
create_default_site() {
    log "Creating the default site: dev.localhost"
    bench new-site dev.localhost \
        --mariadb-root-password your_mariadb_root_password \
        --admin-password admin \
        --mariadb-user-host-login-scope='%'
    if [ $? -eq 0 ]; then
        log "Default site created successfully."
    else
        log "Failed to create the default site. Exiting."
        exit 1
    fi
}

# Function to set the default site
set_default_site() {
    log "Setting the default site to dev.localhost"
    bench use dev.localhost
    if [ $? -eq 0 ]; then
        log "Default site set successfully."
    else
        log "Failed to set the default site."
    fi
}

# Function to install all apps in the apps directory
install_apps() {
    log "Installing apps from the apps directory..."
    for app_dir in apps/*; do
        if [ -d "$app_dir" ] && [ -f "$app_dir/setup.py" ]; then
            app_name=$(basename "$app_dir")
            log "Found app: $app_name. Installing..."
            bench install-app "$app_name"
            if [ $? -eq 0 ]; then
                log "App $app_name installed successfully."
            else
                log "Failed to install app $app_name. Continuing with the next app."
            fi
        else
            log "Skipping $app_dir as it is not a valid app directory."
        fi
    done
}

# Function to configure global settings
configure_global_settings() {
    log "Configuring global settings..."
    bench config --global auto_email_id "admin@dev.localhost"
    bench config --global auto_update_enabled 1
    log "Global settings configured successfully."
}

# Main script execution
check_site_initialized
change_to_bench_directory
create_default_site
set_default_site
install_apps
configure_global_settings

log "Frappe site setup completed successfully."