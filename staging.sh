#!/bin/bash

# Console colors
if [ -t 1 ]; then
    # Terminal supports colors
    BOLD="\033[1m"
    DIM="\033[2m"
    UNDERLINE="\033[4m"
    BLINK="\033[5m"
    INVERT="\033[7m"
    RESET="\033[0m"

    BLACK="\033[30m"
    RED="\033[31m"
    GREEN="\033[32m"
    YELLOW="\033[33m"
    BLUE="\033[34m"
    MAGENTA="\033[35m"
    CYAN="\033[36m"
    WHITE="\033[37m"

    BG_BLACK="\033[40m"
    BG_RED="\033[41m"
    BG_GREEN="\033[42m"
    BG_YELLOW="\033[43m"
    BG_BLUE="\033[44m"
    BG_MAGENTA="\033[45m"
    BG_CYAN="\033[46m"
    BG_WHITE="\033[47m"
else
    # No color support
    BOLD=""
    DIM=""
    UNDERLINE=""
    BLINK=""
    INVERT=""
    RESET=""

    BLACK=""
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    MAGENTA=""
    CYAN=""
    WHITE=""

    BG_BLACK=""
    BG_RED=""
    BG_GREEN=""
    BG_YELLOW=""
    BG_BLUE=""
    BG_MAGENTA=""
    BG_CYAN=""
    BG_WHITE=""
fi

# Constants
INSTALL_DIR="/odoo17/{client_name}-odoo-17"
STAGING_DIR="$INSTALL_DIR/staging"
BASE_PORT=8069
LONGPOLLING_PORT=8072
POSTGRES_PORT={db_port}
PUBLIC_IP="{ip}"

# Display staging banner
show_banner() {
    echo -e "${BG_MAGENTA}${WHITE}${BOLD}"
    echo "  ____  _             _             "
    echo " / ___|| |_ __ _  ___(_)_ __   __ _ "
    echo " \\___ \\| __/ _\` |/ __| | '_ \\ / _\` |"
    echo "  ___) | || (_| | (__| | | | | (_| |"
    echo " |____/ \\__\\__,_|\\___|_|_| |_|\\__, |"
    echo "                              |___/ "
    echo -e "${RESET}"
    echo -e "${CYAN}${BOLD}Odoo Staging Environment Tool for {client_name}${RESET}"
    echo -e "${YELLOW}Property of Azor Data SL (Spain)${RESET}"
    echo -e "${DIM}Created: $(date)${RESET}"
    echo
}

# Log function with colors
log() {
    local level=$1
    shift
    
    case $level in
        INFO)    level_color="${GREEN}";;
        WARNING) level_color="${YELLOW}";;
        ERROR)   level_color="${RED}";;
        SUCCESS) level_color="${GREEN}${BOLD}";;
        *)       level_color="${RESET}";;
    esac
    
    echo -e "${level_color}[$(date '+%Y-%m-%d %H:%M:%S')] [$level]${RESET} $*"
}

# Function to display usage
usage() {
    echo -e "${YELLOW}${BOLD}Usage:${RESET} $0 ${CYAN}[action]${RESET} ${GREEN}[name]${RESET}"
    echo -e "${YELLOW}${BOLD}Actions:${RESET}"
    echo -e "  ${CYAN}create${RESET} ${GREEN}[name]${RESET}  - Create a new staging environment (name optional)"
    echo -e "  ${CYAN}list${RESET}          - List all staging environments"
    echo -e "  ${CYAN}start${RESET} ${GREEN}[name]${RESET}  - Start a staging environment"
    echo -e "  ${CYAN}stop${RESET} ${GREEN}[name]${RESET}   - Stop a staging environment"
    echo -e "  ${CYAN}delete${RESET} ${GREEN}[name]${RESET} - Delete a staging environment"
    echo -e "  ${CYAN}update${RESET} ${GREEN}[name]${RESET} - Update a staging environment from production"
    echo -e "  ${CYAN}cleanup${RESET} ${GREEN}[name]${RESET} - Clean up staging environment(s)"
    echo -e "                  Use '${GREEN}all${RESET}' to remove all staging environments"
    exit 1
}

# Function to get next available number
get_next_number() {
    local max=0
    
    # Check for existing containers instead of directories
    if docker ps -a --format '{{.Names}}' | grep -q "^odoo17-{client_name}-staging$"; then
        max=1
    fi
    
    # Check for numbered staging instances
    docker ps -a --format '{{.Names}}' | grep "^odoo17-{client_name}-staging-[0-9]*$" | while read -r container; do
        num=$(echo "$container" | grep -o '[0-9]*$')
        if [ -n "$num" ] && [ "$num" -gt "$max" ]; then
            max=$num
        fi
    done
    
    # Clean up any orphaned directories
    for d in "$STAGING_DIR"/staging*; do
        if [ -d "$d" ]; then
            name=$(basename "$d")
            if ! docker ps -a --format '{{.Names}}' | grep -q "^odoo17-{client_name}-$name$"; then
                log INFO "Cleaning up orphaned staging directory: ${YELLOW}$d${RESET}"
                rm -rf "$d"
            fi
        fi
    done
    
    echo $((max + 1))
}

# Function to get staging name
get_staging_name() {
    local num=$1
    if [ "$num" -eq 1 ]; then
        echo "staging"
    else
        echo "staging-$num"
    fi
}

# Function to check port availability
check_port() {
    local port=$1
    # Try both netstat and direct connection test
    if ! netstat -tuln | grep -q ":$port " && ! (echo > /dev/tcp/127.0.0.1/$port) 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to get ports
get_ports() {
    local num=$1
    local max_attempts=10  # Try up to 10 different port combinations
    local attempt=0
    local offset
    
    while [ $attempt -lt $max_attempts ]; do
        offset=$(( (num + attempt) * 10 ))
        local web_port=$((BASE_PORT + offset))
        
        # We only need to check web port since others aren't exposed
        if check_port "$web_port"; then
            echo "$web_port"
            return 0
        fi
        
        attempt=$((attempt + 1))
    done
    
    echo "Error: Could not find available web port after $max_attempts attempts"
    return 1
}

# Function to create staging
create_staging() {
    local name=$1
    local num
    
    echo -e "${BG_GREEN}${BLACK}${BOLD} CREATING STAGING ENVIRONMENT ${RESET}"
    
    # Get next number if no name provided
    if [ -z "$name" ]; then
        num=$(get_next_number)
        name=$(get_staging_name "$num")
        log INFO "Auto-generating staging name: ${CYAN}$name${RESET}"
    else
        if [ "$name" = "staging" ]; then
            num=1
        else
            num=$(echo "$name" | grep -o '[0-9]*$')
            if [ -z "$num" ]; then
                log ERROR "Invalid staging name format"
                exit 1
            fi
        fi
        log INFO "Using specified staging name: ${CYAN}$name${RESET}"
    fi
    
    # Check if exists
    if [ -d "$STAGING_DIR/$name" ]; then
        log ERROR "Staging '${CYAN}$name${RESET}' already exists"
        exit 1
    fi
    
    # Get web port
    local web_port
    web_port=$(get_ports "$num")
    if [ $? -ne 0 ]; then
        log ERROR "$web_port"
        exit 1
    fi
    
    echo -e "${YELLOW}${BOLD}Allocated port:${RESET}"
    echo -e "  ${GREEN}Web:${RESET} ${CYAN}$web_port${RESET}"
    
    # Create directory structure
    log INFO "Creating staging environment '${CYAN}$name${RESET}'..."
    mkdir -p "$STAGING_DIR/$name"
    
    # Copy required files
    log INFO "Copying files..."
    for item in config enterprise addons docker-compose.yml; do
        if [ -d "$INSTALL_DIR/$item" ]; then
            log INFO "  Copying directory: ${YELLOW}$item${RESET}"
            cp -r "$INSTALL_DIR/$item" "$STAGING_DIR/$name/"
        else
            log INFO "  Copying file: ${YELLOW}$item${RESET}"
            cp "$INSTALL_DIR/$item" "$STAGING_DIR/$name/"
        fi
    done
    
    # Update odoo.conf
    log INFO "Configuring odoo.conf..."
    local config_file="$STAGING_DIR/$name/config/odoo.conf"
    sed -i "s/^db_name =.*/db_name = postgres_{client_name}_$name/" "$config_file"
    
    # Update docker-compose.yml
    log INFO "Configuring docker-compose.yml..."
    local compose_file="$STAGING_DIR/$name/docker-compose.yml"
    
    # Create a temporary file
    local temp_file=$(mktemp)
    
    # Process the file line by line with proper structure
    while IFS= read -r line; do
        if [[ $line == *":8069"* ]]; then
            # Map web port
            # Handle both formats: with or without 0.0.0.0
            if [[ $line == *"0.0.0.0:"* ]]; then
                echo "      - \"0.0.0.0:$web_port:8069\"" >> "$temp_file"
            else
                echo "      - \"$web_port:8069\"" >> "$temp_file"
            fi
        elif [[ $line == *"container_name: odoo17-{client_name}"* ]]; then
            echo "    container_name: odoo17-{client_name}-$name" >> "$temp_file"
        elif [[ $line == *"container_name: db-{client_name}"* ]]; then
            echo "    container_name: db-{client_name}-$name" >> "$temp_file"
        elif [[ $line == *"POSTGRES_DB=postgres_{client_name}"* ]]; then
            echo "      - POSTGRES_DB=postgres_{client_name}_$name" >> "$temp_file"
        elif [[ $line == *"depends_on:"* ]]; then
            echo "    depends_on:" >> "$temp_file"
            read -r next_line
            echo "      - db" >> "$temp_file"
        elif [[ $line == *"HOST=db"* ]]; then
            echo "      - HOST=db" >> "$temp_file"
        elif [[ $line == *"  web:"* ]]; then
            echo "  web:" >> "$temp_file"
        elif [[ $line == *"  db:"* ]]; then
            echo "  db:" >> "$temp_file"
        else
            echo "$line" >> "$temp_file"
        fi
    done < "$compose_file"
    
    # Replace original file with modified content
    mv "$temp_file" "$compose_file"
    
    # Create required directories
    log INFO "Creating volume directories..."
    mkdir -p "$STAGING_DIR/$name/volumes/odoo-data"
    mkdir -p "$STAGING_DIR/$name/volumes/odoo-data/sessions"
    mkdir -p "$STAGING_DIR/$name/volumes/odoo-data/filestore"
    mkdir -p "$STAGING_DIR/$name/volumes/postgres-data"
    mkdir -p "$STAGING_DIR/$name/logs"
    
    # Set proper permissions
    log INFO "Setting directory permissions..."
    chown -R 101:101 "$STAGING_DIR/$name/volumes/odoo-data"
    chown -R 999:999 "$STAGING_DIR/$name/volumes/postgres-data"
    chmod -R 777 "$STAGING_DIR/$name/volumes/odoo-data"
    chmod -R 777 "$STAGING_DIR/$name/volumes/postgres-data"
    
    log INFO "Starting PostgreSQL container..."
    cd "$STAGING_DIR/$name"
    if ! docker compose up -d db; then
        log ERROR "Failed to start PostgreSQL container"
        exit 1
    fi
    
    log INFO "Waiting for PostgreSQL to start..."
    sleep 10
    
    # Clone production database
    echo -e "${CYAN}${BOLD}=== Cloning production database ===${RESET}"
    
    # Stop Odoo container to ensure consistent backup
    log INFO "Stopping production Odoo for consistent backup..."
    docker stop odoo17-{client_name}
    
    # Copy filestore with proper database name
    log INFO "Copying filestore..."
    mkdir -p "$STAGING_DIR/$name/volumes/odoo-data/filestore/postgres_{client_name}_$name"
    if ! docker cp "odoo17-{client_name}:/var/lib/odoo/filestore/postgres_{client_name}/." \
        "$STAGING_DIR/$name/volumes/odoo-data/filestore/postgres_{client_name}_$name/"; then
        log ERROR "Failed to copy filestore"
        docker start odoo17-{client_name}
        exit 1
    fi
    
    # Reapply permissions after filestore copy
    chown -R 101:101 "$STAGING_DIR/$name/volumes/odoo-data"
    chmod -R 777 "$STAGING_DIR/$name/volumes/odoo-data"
    
    # Simple direct database clone
    log INFO "Creating staging database..."
    # First drop the database if it exists (outside transaction)
    docker exec db-{client_name}-$name psql -U odoo -d template1 -q -c "DROP DATABASE IF EXISTS postgres_{client_name}_$name;" 2>/dev/null
    # Create empty database
    docker exec db-{client_name}-$name psql -U odoo -d template1 -q -c "CREATE DATABASE postgres_{client_name}_$name WITH TEMPLATE template0 OWNER odoo LC_COLLATE 'en_US.UTF-8' LC_CTYPE 'en_US.UTF-8';" 2>/dev/null
    
    # Now dump and restore
    log INFO "Restoring database (this may take a while)..."
    if ! docker exec db-{client_name} pg_dump -U odoo -Fc -Z0 postgres_{client_name} > "/tmp/odoo_staging_$$.dump"; then
        log ERROR "Failed to dump database"
        docker start odoo17-{client_name}
        rm -f "/tmp/odoo_staging_$$.dump"
        exit 1
    fi
    
    if ! docker exec -i db-{client_name}-$name pg_restore -U odoo -d postgres_{client_name}_$name --no-owner --no-privileges --clean --if-exists < "/tmp/odoo_staging_$$.dump" 2>/dev/null; then
        log WARNING "Some non-critical errors occurred during restore"
    fi
    rm -f "/tmp/odoo_staging_$$.dump"
    
    # Verify database was restored properly
    if ! docker exec db-{client_name}-$name psql -U odoo -d postgres_{client_name}_$name -q -t -c "SELECT COUNT(*) FROM res_users;" 2>/dev/null | grep -q '[1-9]'; then
        log ERROR "Database restore failed - database appears empty"
        docker start odoo17-{client_name}
        exit 1
    fi
    
    # Restart production Odoo
    log INFO "Restarting production Odoo..."
    docker start odoo17-{client_name}

    # Start Odoo service first
    log INFO "Starting Odoo service..."
    cd "$STAGING_DIR/$name"
    docker compose up -d web

    log INFO "Waiting for initial startup..."
    sleep 10

    # Now neutralize the database
    echo -e "${CYAN}${BOLD}=== Neutralizing database ===${RESET}"
    log INFO "Neutralizing database..."
    docker exec odoo17-{client_name}-$name odoo neutralize --database postgres_{client_name}_$name

    # Update base URL and configure ribbon (specific to our setup)
    docker exec db-{client_name}-$name psql -U odoo postgres_{client_name}_$name << EOF
BEGIN;

-- Mark web_environment_ribbon for installation
UPDATE ir_module_module SET state = 'to install' WHERE name = 'web_environment_ribbon';
INSERT INTO ir_module_module (name, state)
SELECT 'web_environment_ribbon', 'to install'
WHERE NOT EXISTS (SELECT 1 FROM ir_module_module WHERE name = 'web_environment_ribbon');

COMMIT;
EOF

    # Install ribbon module
    log INFO "Installing ribbon module..."
    docker exec odoo17-{client_name}-$name odoo -d postgres_{client_name}_$name -i web_environment_ribbon --stop-after-init >/dev/null 2>&1

    # Configure ribbon after installation
    log INFO "Configuring ribbon..."
    docker exec db-{client_name}-staging psql -U odoo -d postgres_{client_name}_$name -c "UPDATE ir_config_parameter 
SET value = REPEAT('=', (23 - LENGTH('$name'))/2+1) || '⚠️ ' || UPPER('$name') || ' ⚠️.. NOT FOR PRODUCTION' || REPEAT('=', (23 - LENGTH('$name'))/2)
WHERE key = 'ribbon.name';" >/dev/null 2>&1

    # Update module to apply configuration
    log INFO "Update ribbon module..."
    docker exec odoo17-{client_name}-$name odoo -d postgres_{client_name}_$name -u web_environment_ribbon --stop-after-init >/dev/null 2>&1

    # Restart to ensure clean state
    log INFO "Restarting service..."
    docker compose restart web
    sleep 5

    echo -e "${BG_GREEN}${BLACK}${BOLD} STAGING ENVIRONMENT CREATED SUCCESSFULLY ${RESET}"
    echo -e "  ${GREEN}Path:${RESET} ${YELLOW}$STAGING_DIR/$name${RESET}"
    echo -e "  ${GREEN}Web port:${RESET} ${CYAN}$web_port${RESET} (${UNDERLINE}http://$PUBLIC_IP:$web_port${RESET})"
    echo -e "  ${GREEN}Database:${RESET} ${YELLOW}postgres_{client_name}_$name${RESET}"
    echo -e "  ${GREEN}Status:${RESET} ${GREEN}Running${RESET}"
}

# Function to list stagings
list_stagings() {
    echo -e "${BG_BLUE}${WHITE}${BOLD} AVAILABLE STAGING ENVIRONMENTS ${RESET}"
    echo -e "${DIM}=============================================================${RESET}"
    
    local count=0
    
    for d in "$STAGING_DIR"/staging*; do
        if [ -d "$d" ]; then
            count=$((count + 1))
            name=$(basename "$d")
            echo -e "${CYAN}${BOLD}Name:${RESET} ${YELLOW}$name${RESET}"
            
            # Get container status
            if docker ps -q --filter "name=odoo17-{client_name}-$name" | grep -q .; then
                echo -e "${CYAN}${BOLD}Status:${RESET} ${GREEN}Running${RESET}"
            else
                echo -e "${CYAN}${BOLD}Status:${RESET} ${RED}Stopped${RESET}"
            fi
            
            # Get port
            if [ -f "$d/docker-compose.yml" ]; then
                port=$(grep -o ":[0-9]*\":$BASE_PORT" "$d/docker-compose.yml" | cut -d':' -f2)
                port=${port%\":$BASE_PORT\"}
                echo -e "${CYAN}${BOLD}Web Port:${RESET} ${MAGENTA}$port${RESET} (${UNDERLINE}http://$PUBLIC_IP:$port${RESET})"
            fi
            
            echo -e "${CYAN}${BOLD}Path:${RESET} ${DIM}$d${RESET}"
            echo -e "${DIM}=============================================================${RESET}"
        fi
    done
    
    if [ $count -eq 0 ]; then
        echo -e "${YELLOW}No staging environments found.${RESET}"
        echo -e "${GREEN}Use '${CYAN}$0 create${GREEN}' to create a new staging environment.${RESET}"
    fi
}

# Function to start staging
start_staging() {
    local name=$1
    if [ ! -d "$STAGING_DIR/$name" ]; then
        log ERROR "Staging '${YELLOW}$name${RESET}' does not exist"
        exit 1
    fi
    
    echo -e "${BG_GREEN}${BLACK}${BOLD} STARTING STAGING ENVIRONMENT ${RESET}"
    log INFO "Starting staging '${YELLOW}$name${RESET}'..."
    cd "$STAGING_DIR/$name" || exit 1
    docker compose up -d
    
    # Get port
    port=$(grep -o ":[0-9]*\":$BASE_PORT" docker-compose.yml | cut -d':' -f2)
    port=${port%\":$BASE_PORT\"}
    
    log INFO "Waiting for services to start..."
    sleep 10
    
    # Check service
    max_attempts=30
    attempt=1
    while [ $attempt -le $max_attempts ]; do
        if curl -s "http://localhost:$port/web/database/selector" > /dev/null; then
            echo -e "${BG_GREEN}${BLACK}${BOLD} STAGING STARTED SUCCESSFULLY ${RESET}"
            echo -e "Access at: ${UNDERLINE}http://$PUBLIC_IP:$port${RESET}"
            exit 0
        fi
        log INFO "Waiting for Odoo to start (attempt ${YELLOW}$attempt${RESET}/${YELLOW}$max_attempts${RESET})..."
        sleep 2
        attempt=$((attempt + 1))
    done
    
    log WARNING "Odoo web interface not responding, but containers are running"
}

# Function to stop staging
stop_staging() {
    local name=$1
    if [ ! -d "$STAGING_DIR/$name" ]; then
        log ERROR "Staging '${YELLOW}$name${RESET}' does not exist"
        exit 1
    fi
    
    echo -e "${BG_YELLOW}${BLACK}${BOLD} STOPPING STAGING ENVIRONMENT ${RESET}"
    log INFO "Stopping staging '${YELLOW}$name${RESET}'..."
    cd "$STAGING_DIR/$name" || exit 1
    docker compose down
    echo -e "${BG_GREEN}${BLACK}${BOLD} STAGING STOPPED SUCCESSFULLY ${RESET}"
}

# Function to delete staging
delete_staging() {
    local name=$1
    if [ ! -d "$STAGING_DIR/$name" ]; then
        log ERROR "Staging '${YELLOW}$name${RESET}' does not exist"
        exit 1
    fi
    
    echo -e "${BG_RED}${WHITE}${BOLD} DELETING STAGING ENVIRONMENT ${RESET}"
    
    # Ask for confirmation
    echo -e "${YELLOW}${BOLD}Are you sure you want to delete staging '${CYAN}$name${YELLOW}'? This cannot be undone. (${GREEN}y${YELLOW}/${RED}N${YELLOW})${RESET}"
    read -r confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log INFO "Deletion cancelled"
        exit 0
    fi
    
    # Stop first
    log INFO "Stopping staging '${YELLOW}$name${RESET}'..."
    stop_staging "$name" > /dev/null
    
    # Remove directory
    log INFO "Deleting staging '${YELLOW}$name${RESET}'..."
    rm -rf "$STAGING_DIR/$name"
    echo -e "${BG_GREEN}${BLACK}${BOLD} STAGING DELETED SUCCESSFULLY ${RESET}"
}

# Function to update staging
update_staging() {
    local name=$1
    if [ ! -d "$STAGING_DIR/$name" ]; then
        log ERROR "Staging '${YELLOW}$name${RESET}' does not exist"
        exit 1
    fi
    
    echo -e "${BG_CYAN}${BLACK}${BOLD} UPDATING STAGING ENVIRONMENT ${RESET}"
    log INFO "Updating staging '${YELLOW}$name${RESET}'..."
    
    # Stop containers
    log INFO "Stopping containers..."
    stop_staging "$name" > /dev/null
    
    # Get current port configuration
    local compose_file="$STAGING_DIR/$name/docker-compose.yml"
    local web_port long_port pg_port
    web_port=$(grep -o ":[0-9]*\":$BASE_PORT" "$compose_file" | cut -d':' -f2)
    web_port=${web_port%\":$BASE_PORT\"}
    long_port=$(grep -o ":[0-9]*\":$LONGPOLLING_PORT" "$compose_file" | cut -d':' -f2)
    long_port=${long_port%\":$LONGPOLLING_PORT\"}
    pg_port=$(grep -o ":[0-9]*\":$POSTGRES_PORT" "$compose_file" | cut -d':' -f2)
    pg_port=${pg_port%\":$POSTGRES_PORT\"}
    
    # Update files
    log INFO "Updating configuration files..."
    for item in config enterprise addons docker-compose.yml; do
        if [ -d "$INSTALL_DIR/$item" ]; then
            rm -rf "$STAGING_DIR/$name/$item"
            cp -r "$INSTALL_DIR/$item" "$STAGING_DIR/$name/"
        else
            cp -f "$INSTALL_DIR/$item" "$STAGING_DIR/$name/"
        fi
    done
    
    # Update docker-compose.yml with original ports
    log INFO "Configuring docker-compose.yml..."
    sed -i "s/:$BASE_PORT\"/:$web_port\"/g" "$compose_file"
    sed -i "s/:$LONGPOLLING_PORT\"/:$long_port\"/g" "$compose_file"
    sed -i "s/:$POSTGRES_PORT\"/:$pg_port\"/g" "$compose_file"
    sed -i "s/container_name: odoo17-{client_name}/container_name: odoo17-{client_name}-$name/g" "$compose_file"
    sed -i "s/container_name: db-{client_name}/container_name: db-{client_name}-$name/g" "$compose_file"
    sed -i "s/POSTGRES_DB=postgres_{client_name}/POSTGRES_DB=postgres_{client_name}_$name/g" "$compose_file"
    sed -i "s/PGDATABASE={odoo_db_name}/PGDATABASE=postgres_{client_name}_$name/g" "$compose_file"
    
    # Update base URL and report URL
    log INFO "Updating database parameters..."
    docker exec db-{client_name}-$name psql -U odoo postgres_{client_name}_$name << EOF
BEGIN;

-- Update base URL and report URL
UPDATE ir_config_parameter SET value = 'http://$PUBLIC_IP:$web_port' WHERE key = 'web.base.url';
UPDATE ir_config_parameter SET value = 'localhost:$web_port' WHERE key = 'report.url';
INSERT INTO ir_config_parameter (key, value)
SELECT 'report.url', 'localhost:$web_port'
WHERE NOT EXISTS (SELECT 1 FROM ir_config_parameter WHERE key = 'report.url');

COMMIT;
EOF

    # Sync filestore
    echo -e "${CYAN}${BOLD}=== Syncing filestore ===${RESET}"
    log INFO "Stopping production Odoo..."
    docker stop odoo17-{client_name}
    
    # Clear and recreate filestore directory for clean sync
    log INFO "Clearing and recreating filestore directory..."
    rm -rf "$STAGING_DIR/$name/volumes/odoo-data/filestore/postgres_{client_name}_$name"
    mkdir -p "$STAGING_DIR/$name/volumes/odoo-data/filestore/postgres_{client_name}_$name"
    
    # Copy updated filestore
    log INFO "Copying updated filestore..."
    if ! docker cp "odoo17-{client_name}:/var/lib/odoo/filestore/postgres_{client_name}/." \
        "$STAGING_DIR/$name/volumes/odoo-data/filestore/postgres_{client_name}_$name/"; then
        log WARNING "Failed to sync filestore"
    fi
    
    log INFO "Restarting production Odoo..."
    docker start odoo17-{client_name}
    
    # Reapply all permissions (matching install.sh)
    log INFO "Setting directory permissions..."
    chown -R 101:101 "$STAGING_DIR/$name/volumes/odoo-data"
    chown -R 999:999 "$STAGING_DIR/$name/volumes/postgres-data"
    chmod -R 777 "$STAGING_DIR/$name/volumes/odoo-data"
    chmod -R 777 "$STAGING_DIR/$name/volumes/postgres-data"
    
    # Start containers
    log INFO "Starting staging environment..."
    start_staging "$name"
}

# Function to cleanup staging
cleanup_staging() {
    local name=$1
    
    if [ "$name" = "all" ]; then
        echo -e "${BG_RED}${WHITE}${BOLD} CLEANING UP ALL STAGING ENVIRONMENTS ${RESET}"
        
        # Ask for confirmation
        echo -e "${YELLOW}${BOLD}Are you sure you want to cleanup ${RED}ALL${YELLOW} staging environments? This cannot be undone. (${GREEN}y${YELLOW}/${RED}N${YELLOW})${RESET}"
        read -r confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            log INFO "Cleanup cancelled"
            exit 0
        fi
        
        # Stop and remove all staging containers
        log INFO "Stopping and removing staging containers..."
        if docker ps -a | grep -q "vissecapital-staging"; then
            docker ps -a | grep "vissecapital-staging" | awk '{print $1}' | xargs -r docker rm -f
        else
            log INFO "No staging containers found."
        fi
        
        # Remove staging volumes
        log INFO "Removing staging volumes..."
        if docker volume ls | grep -q "staging"; then
            docker volume ls | grep "staging" | awk '{print $2}' | xargs -r docker volume rm
        else
            log INFO "No staging volumes found."
        fi
        
        # Remove staging networks
        log INFO "Removing staging networks..."
        if docker network ls | grep -q "staging"; then
            docker network ls | grep "staging" | awk '{print $1}' | xargs -r docker network rm
        else
            log INFO "No staging networks found."
        fi
        
        # Remove all staging directories
        log INFO "Removing staging directories..."
        if [ -d "$STAGING_DIR" ] && [ -n "$(ls -A $STAGING_DIR)" ]; then
            rm -rf "$STAGING_DIR"/*
            log SUCCESS "All staging directories removed."
        else
            log INFO "No staging directories found."
        fi
        
        echo -e "${BG_GREEN}${BLACK}${BOLD} ALL STAGING ENVIRONMENTS CLEANED UP SUCCESSFULLY ${RESET}"
        
    else
        # Verify staging exists
        if [ ! -d "$STAGING_DIR/$name" ]; then
            log ERROR "Staging '${YELLOW}$name${RESET}' does not exist"
            exit 1
        fi
        
        echo -e "${BG_RED}${WHITE}${BOLD} CLEANING UP STAGING ENVIRONMENT ${RESET}"
        
        # Ask for confirmation
        echo -e "${YELLOW}${BOLD}Are you sure you want to cleanup staging '${CYAN}$name${YELLOW}'? This cannot be undone. (${GREEN}y${YELLOW}/${RED}N${YELLOW})${RESET}"
        read -r confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            log INFO "Cleanup cancelled"
            exit 0
        fi
        
        log INFO "Cleaning up staging environment '${YELLOW}$name${RESET}'..."
        
        # Stop and remove containers
        log INFO "Stopping and removing containers..."
        if docker ps -a | grep -q "vissecapital-$name\$"; then
            docker ps -a | grep "vissecapital-$name\$" | awk '{print $1}' | xargs -r docker rm -f
        else
            log INFO "No containers found for staging '${YELLOW}$name${RESET}'."
        fi
        
        # Remove volumes
        log INFO "Removing volumes..."
        if docker volume ls | grep -q "_$name\$"; then
            docker volume ls | grep "_$name\$" | awk '{print $2}' | xargs -r docker volume rm
        else
            log INFO "No volumes found for staging '${YELLOW}$name${RESET}'."
        fi
        
        # Remove network
        log INFO "Removing network..."
        if docker network ls | grep -q "_$name\$"; then
            docker network ls | grep "_$name\$" | awk '{print $1}' | xargs -r docker network rm
        else
            log INFO "No network found for staging '${YELLOW}$name${RESET}'."
        fi
        
        # Remove directory
        log INFO "Removing staging directory..."
        rm -rf "$STAGING_DIR/$name"
        
        echo -e "${BG_GREEN}${BLACK}${BOLD} STAGING ENVIRONMENT CLEANED UP SUCCESSFULLY ${RESET}"
    fi
}

# Main script
show_banner

case "$1" in
    create)
        create_staging "$2"
        ;;
    list)
        list_stagings
        ;;
    start)
        if [ -z "$2" ]; then
            usage
        fi
        start_staging "$2"
        ;;
    stop)
        if [ -z "$2" ]; then
            usage
        fi
        stop_staging "$2"
        ;;
    delete)
        if [ -z "$2" ]; then
            usage
        fi
        delete_staging "$2"
        ;;
    update)
        if [ -z "$2" ]; then
            usage
        fi
        update_staging "$2"
        ;;
    cleanup)
        if [ -z "$2" ]; then
            usage
        fi
        cleanup_staging "$2"
        ;;
    *)
        usage
        ;;
esac 