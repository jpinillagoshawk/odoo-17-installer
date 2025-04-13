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
INSTALL_DIR="{path_to_install}/{client_name}-odoo-17"
BACKUP_DIR="$INSTALL_DIR/backups"
DB_CONTAINER="{db_container_name}"
DB_NAME="{odoo_db_name}"
DB_USER="{db_user}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
TEMP_DIR="/tmp/odoo_backup_${TIMESTAMP}"

# Display backup banner
show_banner() {
    echo -e "${BG_CYAN}${BLACK}${BOLD}"
    echo "  ____            _                 "
    echo " | __ )  __ _  ___| | ___   _ _ __  "
    echo " |  _ \\ / _\` |/ __| |/ / | | | '_ \\ "
    echo " | |_) | (_| | (__|   <| |_| | |_) |"
    echo " |____/ \\__,_|\\___|_|\\_\\\\__,_| .__/ "
    echo "                             |_|    "
    echo -e "${RESET}"
    echo -e "${CYAN}${BOLD}Odoo Backup & Restore Tool for {client_name}${RESET}"
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
    echo -e "${YELLOW}${BOLD}Usage:${RESET} $0 ${CYAN}[command]${RESET} ${GREEN}[options]${RESET}"
    echo -e "${YELLOW}${BOLD}Commands:${RESET}"
    echo -e "  ${CYAN}backup${RESET} ${GREEN}[daily|monthly]${RESET}  - Create a backup"
    echo -e "  ${CYAN}restore${RESET} ${GREEN}[backup_file]${RESET}   - Restore from a backup file"
    echo -e "                           If no file specified, shows interactive selection"
    echo -e "  ${CYAN}list${RESET}                    - List available backups with interactive restore option"
    exit 1
}

# Function to create backup
create_backup() {
    local type=$1
    local backup_path
    local current_dir=$(pwd)
    local backup_failed=false
    local backup_file=""

    # Set backup path based on type
    if [ "$type" = "daily" ]; then
        backup_path="$BACKUP_DIR/daily"
        # Keep only last 7 days and clean up their filestore data
        log INFO "Cleaning up old daily backups..."
        for old_backup in $(find "$backup_path" -type f -mtime +7 -name "*.zip"); do
            log INFO "Processing old backup: ${YELLOW}$(basename "$old_backup")${RESET}"
            # Extract the filestore paths from the backup before deleting
            if [ -f "$old_backup" ]; then
                local temp_extract="/tmp/cleanup_$(basename "$old_backup" .zip)"
                mkdir -p "$temp_extract"
                unzip -q "$old_backup" filestore/*/filestore.list -d "$temp_extract" || true
                if [ -f "$temp_extract/filestore/filestore.list" ]; then
                    while IFS= read -r path; do
                        if [ -d "$INSTALL_DIR/volumes/odoo-data/filestore/$path" ]; then
                            log INFO "Removing old filestore data: ${YELLOW}$path${RESET}"
                            rm -rf "$INSTALL_DIR/volumes/odoo-data/filestore/$path"
                        fi
                    done < "$temp_extract/filestore/filestore.list"
                fi
                rm -rf "$temp_extract"
            fi
            rm -f "$old_backup"
        done
    elif [ "$type" = "monthly" ]; then
        backup_path="$BACKUP_DIR/monthly"
        # Keep only last 6 months and clean up their filestore data
        log INFO "Cleaning up old monthly backups..."
        for old_backup in $(find "$backup_path" -type f -mtime +180 -name "*.zip"); do
            log INFO "Processing old backup: ${YELLOW}$(basename "$old_backup")${RESET}"
            # Extract the filestore paths from the backup before deleting
            if [ -f "$old_backup" ]; then
                local temp_extract="/tmp/cleanup_$(basename "$old_backup" .zip)"
                mkdir -p "$temp_extract"
                unzip -q "$old_backup" filestore/*/filestore.list -d "$temp_extract" || true
                if [ -f "$temp_extract/filestore/filestore.list" ]; then
                    while IFS= read -r path; do
                        if [ -d "$INSTALL_DIR/volumes/odoo-data/filestore/$path" ]; then
                            log INFO "Removing old filestore data: ${YELLOW}$path${RESET}"
                            rm -rf "$INSTALL_DIR/volumes/odoo-data/filestore/$path"
                        fi
                    done < "$temp_extract/filestore/filestore.list"
                fi
                rm -rf "$temp_extract"
            fi
            rm -f "$old_backup"
        done
    else
        usage
    fi

    # Set the backup filename
    backup_file="$backup_path/backup_${TIMESTAMP}.zip"

    echo -e "${CYAN}${BOLD}=== Creating ${UNDERLINE}$type${RESET}${CYAN}${BOLD} backup ===${RESET}"
    
    # Create backup directory if it doesn't exist
    mkdir -p "$backup_path"
    mkdir -p "$TEMP_DIR"

    # Change to INSTALL_DIR for docker compose commands
    cd "$INSTALL_DIR"

    # Stop Odoo container for consistent backup
    log INFO "Stopping Odoo service..."
    docker compose stop web || backup_failed=true
    
    # Use trap to ensure cleanup on exit
    trap 'cleanup_and_restart "$current_dir" "$backup_file" "$backup_failed" "$TEMP_DIR/filestore"' EXIT
    
    if [ "$backup_failed" = true ]; then
        log ERROR "Failed to stop Odoo service"
        exit 1
    fi

    # Backup database using Odoo's backup format
    log INFO "Backing up database..."
    if ! docker exec $DB_CONTAINER pg_dump -Fc -U $DB_USER $DB_NAME > "$TEMP_DIR/dump.backup"; then
        log ERROR "Database backup failed"
        backup_failed=true
        exit 1
    fi
    
    # Backup filestore directly from volume
    log INFO "Backing up filestore..."
    if ! cp -a "$INSTALL_DIR/volumes/odoo-data/filestore/." "$TEMP_DIR/filestore/"; then
        log ERROR "Filestore backup failed"
        backup_failed=true
        exit 1
    fi

    # Update timestamps to reflect backup time
    log INFO "Updating filestore timestamps..."
    find "$TEMP_DIR/filestore" -type f -exec touch {} +
    
    # Create a list of filestore paths for future cleanup
    log INFO "Creating filestore path list..."
    find "$TEMP_DIR/filestore" -type d -mindepth 1 -maxdepth 1 -printf "%f\n" > "$TEMP_DIR/filestore/filestore.list"
    
    # Create zip archive
    log INFO "Creating backup archive..."
    cd "$TEMP_DIR"
    if ! zip -r "$backup_file" dump.backup filestore/; then
        log ERROR "Archive creation failed"
        backup_failed=true
        exit 1
    fi

    # Return to INSTALL_DIR for docker-compose
    cd "$INSTALL_DIR"

    # Cleanup will be handled by trap
    rm -rf "$TEMP_DIR"
    
    log SUCCESS "Backup completed: ${YELLOW}$backup_file${RESET}"
    backup_failed=false
}

# Function to handle cleanup and container restart
cleanup_and_restart() {
    local original_dir=$1
    local backup_file=$2
    local failed=$3
    local filestore_temp=$4
    
    # Always try to restart Odoo
    log INFO "Ensuring Odoo service is running..."
    cd "$INSTALL_DIR"
    docker compose start web
    
    # If backup failed, remove the partial backup file and clean temporary filestore
    if [ "$failed" = true ]; then
        echo -e "${BG_RED}${WHITE}${BOLD} BACKUP FAILED ${RESET}"
        
        if [ -n "$backup_file" ] && [ -f "$backup_file" ]; then
            log WARNING "Removing partial backup file: ${YELLOW}$backup_file${RESET}"
            rm -f "$backup_file"
        fi
        if [ -n "$filestore_temp" ] && [ -d "$filestore_temp" ]; then
            log WARNING "Cleaning up temporary filestore data..."
            rm -rf "$filestore_temp"
        fi
    else
        echo -e "${BG_GREEN}${BLACK}${BOLD} BACKUP COMPLETED SUCCESSFULLY ${RESET}"
    fi
    
    # Return to original directory
    cd "$original_dir"
    
    # Clean up temp directory if it exists
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
    
    # Remove trap
    trap - EXIT
}

# Function to extract database name from backup file
extract_db_name_from_backup() {
    local backup_file=$1
    local extraction_dir="$TEMP_DIR/extract_db_name"
    
    # Create temporary directory
    mkdir -p "$extraction_dir"
    
    # Extract dump file to determine database name
    log INFO "Extracting metadata from backup to determine database name..."
    unzip -q "$backup_file" -d "$extraction_dir" || return 1
    
    # Check for dump.backup (custom format) first
    if [ -f "$extraction_dir/dump.backup" ]; then
        # Use pg_restore to get database name from custom format backup
        local extracted_db_name=$(docker exec -i $DB_CONTAINER pg_restore -l "$extraction_dir/dump.backup" 2>/dev/null | grep -m 1 -oP "DATABASE - \K[^\s]+" || echo "")
        
        # If extraction failed, try another approach
        if [ -z "$extracted_db_name" ]; then
            # Try to grep first database reference if available
            extracted_db_name=$(docker exec -i $DB_CONTAINER bash -c "cat < $extraction_dir/dump.backup | strings" 2>/dev/null | grep -m 1 -oP "CREATE DATABASE \K[^\s;]+" || echo "")
        fi
    elif [ -f "$extraction_dir/dump.sql" ]; then
        # Try to extract database name from SQL dump
        extracted_db_name=$(grep -m 1 -oP "CREATE DATABASE \K[^\s;]+" "$extraction_dir/dump.sql" 2>/dev/null || echo "")
    else
        log WARNING "Could not find database dump in backup"
        rm -rf "$extraction_dir"
        return 1
    fi
    
    # Clean up
    rm -rf "$extraction_dir"
    
    if [ -n "$extracted_db_name" ]; then
        log INFO "Extracted database name: ${YELLOW}$extracted_db_name${RESET}"
        echo "$extracted_db_name"
        return 0
    else
        log WARNING "Could not extract database name from backup"
        # Don't output anything when extraction fails
        return 1
    fi
}

# Function to update docker-compose.yml with new database name
update_docker_compose() {
    local new_db_name=$1
    local docker_compose_file="$INSTALL_DIR/docker-compose.yml"
    
    # Validate database name - prevent error message from being used as DB name
    if [[ -z "$new_db_name" || "$new_db_name" == *"WARNING"* || "$new_db_name" == *"["* ]]; then
        log WARNING "Invalid database name. Using configured default: ${YELLOW}${DB_NAME}${RESET}"
        new_db_name="$DB_NAME"
    fi
    
    log INFO "Updating docker-compose.yml with new database name: ${YELLOW}$new_db_name${RESET}"
    
    if [ ! -f "$docker_compose_file" ]; then
        log ERROR "docker-compose.yml not found at $docker_compose_file"
        return 1
    fi
    
    # Create backup of docker-compose.yml
    cp "$docker_compose_file" "${docker_compose_file}.bak.${TIMESTAMP}"
    
    # Update PGDATABASE in web service
    sed -i "s/PGDATABASE=.*/PGDATABASE=$new_db_name/g" "$docker_compose_file"
    
    # Update POSTGRES_DB in db service
    sed -i "s/POSTGRES_DB=.*/POSTGRES_DB=$new_db_name/g" "$docker_compose_file"
    
    log SUCCESS "Updated docker-compose.yml configuration"
    return 0
}

# Function to update odoo.conf with new database name
update_odoo_conf() {
    local new_db_name=$1
    local odoo_conf_file="$INSTALL_DIR/config/odoo.conf"
    
    # Validate database name - prevent error message from being used as DB name
    if [[ -z "$new_db_name" || "$new_db_name" == *"WARNING"* || "$new_db_name" == *"["* ]]; then
        log WARNING "Invalid database name. Using configured default: ${YELLOW}${DB_NAME}${RESET}"
        new_db_name="$DB_NAME"
    fi
    
    log INFO "Updating odoo.conf with new database name: ${YELLOW}$new_db_name${RESET}"
    
    if [ ! -f "$odoo_conf_file" ]; then
        log WARNING "odoo.conf not found at $odoo_conf_file"
        return 1
    fi
    
    # Create backup of odoo.conf
    cp "$odoo_conf_file" "${odoo_conf_file}.bak.${TIMESTAMP}"
    
    # Update database configurations
    sed -i "s/^db_name = .*/db_name = $new_db_name/" "$odoo_conf_file"
    sed -i "s/^dbfilter = .*/dbfilter = $new_db_name/" "$odoo_conf_file"
    sed -i "s/^database = .*/database = $new_db_name/" "$odoo_conf_file"
    
    log SUCCESS "Updated odoo.conf configuration"
    return 0
}

# Function to restore backup with meticulous filestore handling
restore_backup() {
    local backup_file=$1
    local current_dir=$(pwd)
    local temp_dir="/tmp/odoo_meticulous_restore_$(date +%s)"
    local dump_file=""
    local is_custom_format=false
    local odoo_uid=101  # Default Odoo UID in standard images
    local odoo_gid=101  # Default Odoo GID in standard images
    
    echo -e "${BG_MAGENTA}${WHITE}${BOLD} METICULOUS RESTORE OPERATION ${RESET}"
    log INFO "Starting meticulous restore from: ${YELLOW}$backup_file${RESET}"
    
    # Step 1: Start fresh - stop and remove existing containers
    cd "$INSTALL_DIR" || {
        log ERROR "Failed to change to installation directory: $INSTALL_DIR"
        return 1
    }
    
    log INFO "Stopping all services and removing containers..."
    docker compose down --remove-orphans
    
    # Step 2: Extract backup to clean temporary directory
    log INFO "Extracting backup to clean temporary directory..."
    rm -rf "$temp_dir"
    mkdir -p "$temp_dir"
    
    if ! unzip -q "$backup_file" -d "$temp_dir"; then
        log ERROR "Failed to extract backup file. Check if it's a valid zip archive."
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Verify backup contents
    if [ -f "$temp_dir/dump.backup" ]; then
        log INFO "Found backup in custom format (dump.backup)"
        dump_file="dump.backup"
        is_custom_format=true
    elif [ -f "$temp_dir/dump.sql" ]; then
        log INFO "Found backup in SQL format (dump.sql)"
        dump_file="dump.sql"
        is_custom_format=false
    else
        log ERROR "Invalid backup: Missing database dump file (dump.backup or dump.sql)"
        rm -rf "$temp_dir"
        return 1
    fi
    
    if [ ! -d "$temp_dir/filestore" ]; then
        log ERROR "Invalid backup: Missing filestore directory"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Step 3: Start ONLY database service
    log INFO "Starting only database service..."
    docker compose up -d db
    
    # Wait for database to be ready
    log INFO "Waiting for database to initialize (up to 30s)..."
    local max_attempts=15
    local attempt=0
    local db_ready=false
    
    while [ $attempt -lt $max_attempts ]; do
        if docker exec "$DB_CONTAINER" pg_isready -U "$DB_USER" -d postgres &>/dev/null; then
            db_ready=true
            break
        fi
        attempt=$((attempt + 1))
        sleep 2
    done
    
    if [ "$db_ready" = false ]; then
        log ERROR "Database did not become ready within the timeout period"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Step 4: Create empty database
    log INFO "Creating empty database: ${YELLOW}$DB_NAME${RESET}"
    docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d postgres -c "DROP DATABASE IF EXISTS \"$DB_NAME\";" &>/dev/null
    docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d postgres -c "CREATE DATABASE \"$DB_NAME\" OWNER \"$DB_USER\";" &>/dev/null || {
        log ERROR "Failed to create database"
        rm -rf "$temp_dir"
        return 1
    }
    
    # Step 5: Restore database dump
    log INFO "Restoring database dump..."
    if [ "$is_custom_format" = true ]; then
        cat "$temp_dir/$dump_file" | docker exec -i "$DB_CONTAINER" pg_restore -U "$DB_USER" -d "$DB_NAME" --no-owner --role="$DB_USER" -v &>/dev/null || {
            log ERROR "Failed to restore database dump (custom format)"
            rm -rf "$temp_dir"
            return 1
        }
    else
        cat "$temp_dir/$dump_file" | docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" &>/dev/null || {
            log ERROR "Failed to restore database dump (SQL format)"
            rm -rf "$temp_dir"
            return 1
        }
    fi
    log SUCCESS "Database restored successfully"
    
    # Step 6: CRITICAL - Restore filestore meticulously
    local host_filestore_path="$INSTALL_DIR/volumes/odoo-data/filestore"
    
    log INFO "Meticulously restoring filestore to: ${YELLOW}$host_filestore_path${RESET}"
    # Ensure target directory is clean and exists
    rm -rf "$host_filestore_path"
    mkdir -p "$host_filestore_path"
    
    # Copy preserving all attributes (-a flag is vital)
    if ! cp -a "$temp_dir/filestore/." "$host_filestore_path/"; then
        log ERROR "Failed to copy filestore with attributes preserved"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Verify copy success by comparing file counts
    local src_count=$(find "$temp_dir/filestore" -type f | wc -l)
    local dst_count=$(find "$host_filestore_path" -type f | wc -l)
    
    if [ "$src_count" -ne "$dst_count" ]; then
        log WARNING "Filestore copy might be incomplete: Source has $src_count files, destination has $dst_count files"
    else
        log SUCCESS "Filestore copy verified ($src_count files copied)"
    fi
    
    # Step 7: CRITICAL - Set correct permissions
    log INFO "Setting correct permissions on filestore..."
    # Apply ownership recursively
    chown -R "$odoo_uid:$odoo_gid" "$host_filestore_path"
    # Apply directory permissions
    find "$host_filestore_path" -type d -exec chmod 755 {} \;
    # Apply file permissions
    find "$host_filestore_path" -type f -exec chmod 644 {} \;
    log SUCCESS "Permissions set correctly"
    
    # Step 8: DO NOT MODIFY DATABASE - Skip the UPDATE ir_attachment SET store_fname = NULL
    log INFO "Preserving original attachment links (skipping store_fname modifications)"
    
    # Step 9: Start all services
    log INFO "Starting all services..."
    docker compose up -d
    log INFO "Waiting for Odoo to initialize (30s)..."
    sleep 30
    
    # Step 10: Clear filesystem asset cache
    log INFO "Clearing filesystem asset cache..."
    local odoo_assets_path="$INSTALL_DIR/volumes/odoo-data/.local/share/Odoo/assets"
    rm -rf "${odoo_assets_path:?}/"*
    
    # Get container names for both Odoo and database
    local odoo_container=$(docker ps --format '{{.Names}}' | grep -E 'odoo|web' | head -1)
    
    # Also clear internal container asset cache if container exists
    if [ -n "$odoo_container" ]; then
        log INFO "Clearing internal Odoo asset cache in container: ${YELLOW}$odoo_container${RESET}"
        docker exec "$odoo_container" rm -rf /var/lib/odoo/.local/share/Odoo/assets/* 2>/dev/null || true
    fi
    
    # Step 11: Trigger asset regeneration
    log INFO "Triggering asset regeneration as Odoo user..."
    if [ -n "$odoo_container" ]; then
        docker exec -u "$odoo_uid" "$odoo_container" odoo --database="$DB_NAME" --update=base --stop-after-init --workers=0 &>/dev/null || {
            log WARNING "Asset regeneration command failed, but continuing..."
        }
        
        # Ensure Odoo service is running
        log INFO "Ensuring Odoo service is running..."
        docker compose start web
        sleep 5
    else
        log WARNING "Could not find Odoo container to trigger asset regeneration"
    fi
    
    # Step 12: Clear browser cache & test - informational message
    log INFO "Manual step required: Clear browser cache thoroughly and check icons/images"
    
    # Step 13: Cleanup
    log INFO "Cleaning up temporary directory..."
    rm -rf "$temp_dir"
    
    # Return to original directory
    cd "$current_dir"
    
    log SUCCESS "Meticulous restore completed successfully!"
    echo -e "${YELLOW}IMPORTANT:${RESET} For proper display of all images:"
    echo -e "1. ${BOLD}Clear browser cache${RESET} thoroughly (or use incognito/private mode)"
    echo -e "2. If any image is still missing, it may require manual re-upload"
    
    return 0
}

# Function to list available backups
list_backups() {
    local daily_count=0
    local monthly_count=0
    local backups=()
    
    echo -e "${BG_BLUE}${WHITE}${BOLD} AVAILABLE BACKUPS ${RESET}"
    echo -e "${CYAN}${BOLD}Daily backups:${RESET}"
    echo -e "${DIM}-----------------------------------------------${RESET}"
    while IFS= read -r backup; do
        if [ -f "$backup" ]; then
            daily_count=$((daily_count + 1))
            backups+=("$backup")
            local size=$(du -h "$backup" | cut -f1)
            local date=$(date -r "$backup" "+%Y-%m-%d %H:%M:%S")
            echo -e "  ${GREEN}${BOLD}$daily_count)${RESET} ${YELLOW}$(basename "$backup")${RESET} (${CYAN}$size${RESET}) - ${DIM}$date${RESET}"
        fi
    done < <(find "$BACKUP_DIR/daily" -maxdepth 1 -type f -name "backup_*.zip" -print0 | sort -z -r | tr '\0' '\n')
    
    echo -e "\n${CYAN}${BOLD}Monthly backups:${RESET}"
    echo -e "${DIM}-----------------------------------------------${RESET}"
    while IFS= read -r backup; do
        if [ -f "$backup" ]; then
            local count=$((daily_count + monthly_count + 1))
            monthly_count=$((monthly_count + 1))
            backups+=("$backup")
            local size=$(du -h "$backup" | cut -f1)
            local date=$(date -r "$backup" "+%Y-%m-%d %H:%M:%S")
            echo -e "  ${GREEN}${BOLD}$count)${RESET} ${YELLOW}$(basename "$backup")${RESET} (${CYAN}$size${RESET}) - ${DIM}$date${RESET}"
        fi
    done < <(find "$BACKUP_DIR/monthly" -maxdepth 1 -type f -name "backup_*.zip" -print0 | sort -z -r | tr '\0' '\n')
    
    if [ $((daily_count + monthly_count)) -eq 0 ]; then
        echo -e "${RED}${BOLD}No backups found.${RESET}"
        exit 1
    fi
    
    echo -e "\n${YELLOW}${BOLD}Select a backup to restore (${GREEN}1-$((daily_count + monthly_count))${YELLOW}) or 'q' to quit:${RESET}"
    local selection
    while true; do
        read -r selection
        if [[ "$selection" == "q" ]]; then
            echo -e "${CYAN}Operation cancelled.${RESET}"
            exit 0
        elif [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le $((daily_count + monthly_count)) ]; then
            local selected_backup="${backups[$((selection-1))]}"
            echo -e "\n${GREEN}${BOLD}You selected:${RESET} ${YELLOW}$(basename "$selected_backup")${RESET}"
            
            # Confirmation loop
            while true; do
                echo -e "${YELLOW}${BOLD}Are you sure you want to restore this backup?${RESET} ${GREEN}([Y]/n)${RESET}"
                local confirm
                read -r confirm
                
                # Convert to lowercase for comparison
                confirm=$(echo "$confirm" | tr '[:upper:]' '[:lower:]')
                
                if [[ -z "$confirm" ]] || [[ "$confirm" == "y" ]] || [[ "$confirm" == "yes" ]]; then
                    restore_backup "$selected_backup"
                    break
                elif [[ "$confirm" == "n" ]] || [[ "$confirm" == "no" ]]; then
                    echo -e "${CYAN}Operation cancelled.${RESET}"
                    exit 0
                else
                    echo -e "${RED}Invalid option:${RESET} $confirm"
                    continue
                fi
            done
            break
        else
            echo -e "${RED}Invalid selection. Please enter a number between ${GREEN}1${RESET} and ${GREEN}$((daily_count + monthly_count))${RESET} or 'q' to quit:${RESET}"
        fi
    done
}

# Main script
show_banner

case "$1" in
    backup)
        create_backup "$2"
        ;;
    restore)
        if [ -z "$2" ]; then
            list_backups
        else
            restore_backup "$2"
        fi
        ;;
    list)
        list_backups
        ;;
    *)
        usage
        ;;
esac