#!/bin/bash

# Odoo Permissions Fix Script
# This script fixes filestore permissions for database operations like restore

# Colors
if [ -t 1 ]; then
    # Terminal supports colors
    BOLD="\033[1m"
    RESET="\033[0m"
    GREEN="\033[32m"
    YELLOW="\033[33m"
    RED="\033[31m"
else
    # No color support
    BOLD=""
    RESET=""
    GREEN=""
    YELLOW=""
    RED=""
fi

# Detect environment
IS_WINDOWS=false
if [[ "$(uname -s)" == *"MINGW"* ]] || [[ "$(uname -s)" == *"MSYS"* ]] || [[ "$(uname -s)" == *"CYGWIN"* ]]; then
    IS_WINDOWS=true
    echo -e "${YELLOW}Windows environment detected${RESET}"
fi

# Container name
ODOO_CONTAINER="{odoo_container_name}"
INSTALL_DIR="$(pwd)"

echo -e "${BOLD}Odoo Permissions Fix Tool${RESET}"
echo -e "${GREEN}This tool fixes permissions for database operations${RESET}"
echo

# Check if Docker is running and the container exists
if ! docker ps | grep -q "$ODOO_CONTAINER"; then
    echo -e "${RED}Error: Odoo container ($ODOO_CONTAINER) is not running!${RESET}"
    echo -e "${YELLOW}Please start the container before running this script.${RESET}"
    exit 1
fi

echo -e "${YELLOW}Fixing filestore permissions...${RESET}"

if [ "$IS_WINDOWS" = "true" ]; then
    echo -e "${YELLOW}Windows environment detected - special handling required${RESET}"
    echo "Creating directory structure without changing permissions..."
    
    # On Windows, just ensure the directories exist without trying to change permissions
    docker exec $ODOO_CONTAINER sh -c "mkdir -p /var/lib/odoo/filestore" || true
    
    echo -e "${GREEN}Directory structure created.${RESET}"
    echo -e "${YELLOW}For Windows Docker volumes, follow these steps to fix permissions:${RESET}"
    echo "1. Open Explorer and navigate to: $INSTALL_DIR/volumes/odoo-data"
    echo "2. Right-click on 'filestore' folder → Properties → Security tab"
    echo "3. Click 'Edit' and then 'Add'"
    echo "4. Enter 'Everyone' and click 'Check Names' → OK"
    echo "5. Select 'Everyone' and check 'Full control' → Apply → OK"
    echo "6. Restart Docker Desktop and the Odoo container"
    
    echo -e "${YELLOW}After setting permissions in Windows Explorer, restart containers with:${RESET}"
    echo "cd $INSTALL_DIR && docker-compose down && docker-compose up -d"
else
    # Directly fix permissions on the host
    echo "Setting host filesystem permissions..."
    chmod -R 777 "$INSTALL_DIR/volumes/odoo-data/filestore" 2>/dev/null || echo "Warning: Could not set permissions for filestore directory"
    chown -R 101:101 "$INSTALL_DIR/volumes/odoo-data/filestore" 2>/dev/null || echo "Warning: Could not set ownership for filestore directory"
fi

echo -e "${GREEN}Filestore permissions fixed!${RESET}"
echo -e "${BOLD}You should now be able to restore databases.${RESET}"
echo

exit 0 