#!/bin/bash

# Constants
INSTALL_DIR="/{client_name}-odoo-17"
BACKUP_DIR="$INSTALL_DIR/backups"
CONTAINER_NAME="odoo17-{client_name}"
DB_CONTAINER="db-{client_name}"
DB_NAME="postgres_{client_name}"
DB_USER="odoo"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
TEMP_DIR="/tmp/odoo_backup_${TIMESTAMP}"

# Function to display usage
usage() {
    echo "Usage: $0 [command] [options]"
    echo "Commands:"
    echo "  backup [daily|monthly]  - Create a backup"
    echo "  restore [backup_file]   - Restore from a backup file"
    echo "                           If no file specified, shows interactive selection"
    echo "  list                    - List available backups with interactive restore option"
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
        echo "Cleaning up old daily backups..."
        for old_backup in $(find "$backup_path" -type f -mtime +7 -name "*.zip"); do
            echo "Processing old backup: $old_backup"
            # Extract the filestore paths from the backup before deleting
            if [ -f "$old_backup" ]; then
                local temp_extract="/tmp/cleanup_$(basename "$old_backup" .zip)"
                mkdir -p "$temp_extract"
                unzip -q "$old_backup" filestore/*/filestore.list -d "$temp_extract" || true
                if [ -f "$temp_extract/filestore/filestore.list" ]; then
                    while IFS= read -r path; do
                        if [ -d "$INSTALL_DIR/volumes/odoo-data/filestore/$path" ]; then
                            echo "Removing old filestore data: $path"
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
        echo "Cleaning up old monthly backups..."
        for old_backup in $(find "$backup_path" -type f -mtime +180 -name "*.zip"); do
            echo "Processing old backup: $old_backup"
            # Extract the filestore paths from the backup before deleting
            if [ -f "$old_backup" ]; then
                local temp_extract="/tmp/cleanup_$(basename "$old_backup" .zip)"
                mkdir -p "$temp_extract"
                unzip -q "$old_backup" filestore/*/filestore.list -d "$temp_extract" || true
                if [ -f "$temp_extract/filestore/filestore.list" ]; then
                    while IFS= read -r path; do
                        if [ -d "$INSTALL_DIR/volumes/odoo-data/filestore/$path" ]; then
                            echo "Removing old filestore data: $path"
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

    echo "Creating $type backup..."

    # Create backup directory if it doesn't exist
    mkdir -p "$backup_path"
    mkdir -p "$TEMP_DIR"

    # Change to INSTALL_DIR for docker-compose commands
    cd "$INSTALL_DIR"

    # Stop Odoo container for consistent backup
    echo "Stopping Odoo service..."
    docker stop $CONTAINER_NAME || backup_failed=true

    # Use trap to ensure cleanup on exit
    trap 'cleanup_and_restart "$current_dir" "$backup_file" "$backup_failed" "$TEMP_DIR/filestore"' EXIT

    if [ "$backup_failed" = true ]; then
        echo "Failed to stop Odoo service"
        exit 1
    fi

    # Backup database using Odoo's backup format
    echo "Backing up database..."
    if ! docker exec $DB_CONTAINER pg_dump -Fc -U $DB_USER $DB_NAME > "$TEMP_DIR/dump.backup"; then
        echo "Database backup failed"
        backup_failed=true
        exit 1
    fi

    # Backup filestore directly from volume
    echo "Backing up filestore..."
    if ! cp -a "$INSTALL_DIR/volumes/odoo-data/filestore/." "$TEMP_DIR/filestore/"; then
        echo "Filestore backup failed"
        backup_failed=true
        exit 1
    fi

    # Update timestamps to reflect backup time
    echo "Updating filestore timestamps..."
    find "$TEMP_DIR/filestore" -type f -exec touch {} +

    # Create a list of filestore paths for future cleanup
    echo "Creating filestore path list..."
    find "$TEMP_DIR/filestore" -type d -mindepth 1 -maxdepth 1 -printf "%f\n" > "$TEMP_DIR/filestore/filestore.list"

    # Create zip archive
    echo "Creating backup archive..."
    cd "$TEMP_DIR"
    if ! zip -r "$backup_file" dump.backup filestore/; then
        echo "Archive creation failed"
        backup_failed=true
        exit 1
    fi

    # Return to INSTALL_DIR for docker-compose
    cd "$INSTALL_DIR"

    # Cleanup will be handled by trap
    rm -rf "$TEMP_DIR"

    echo "Backup completed: $backup_file"
    backup_failed=false
}

# Function to handle cleanup and container restart
cleanup_and_restart() {
    local original_dir=$1
    local backup_file=$2
    local failed=$3
    local filestore_temp=$4

    # Always try to restart Odoo
    echo "Ensuring Odoo service is running..."
    cd "$INSTALL_DIR"
    docker start $CONTAINER_NAME || docker run -d --name $CONTAINER_NAME \
        --link $DB_CONTAINER:db \
        -p 8069:8069 \
        -v "$INSTALL_DIR/config:/etc/odoo" \
        -v "$INSTALL_DIR/volumes/odoo-data:/var/lib/odoo" \
        -v "$INSTALL_DIR/enterprise:/mnt/enterprise" \
        -v "$INSTALL_DIR/addons:/mnt/extra-addons" \
        -v "$INSTALL_DIR/logs:/var/log/odoo" \
        -e HOST=db \
        -e PORT=5432 \
        -e USER=$DB_USER \
        -e PASSWORD={client_password} \
        -e PROXY_MODE=True \
        odoo:17.0 -- --init=base -d $DB_NAME

    # If backup failed, remove the partial backup file and clean temporary filestore
    if [ "$failed" = true ]; then
        if [ -n "$backup_file" ] && [ -f "$backup_file" ]; then
            echo "Removing partial backup file: $backup_file"
            rm -f "$backup_file"
        fi
        if [ -n "$filestore_temp" ] && [ -d "$filestore_temp" ]; then
            echo "Cleaning up temporary filestore data..."
            rm -rf "$filestore_temp"
        fi
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

# Function to restore backup
restore_backup() {
    local backup_file=$1
    local current_dir=$(pwd)

    if [ ! -f "$backup_file" ]; then
        echo "Error: Backup file not found: $backup_file"
        exit 1
    fi

    if [[ "$backup_file" != *.zip ]]; then
        echo "Error: Backup file must be a .zip file"
        exit 1
    fi

    echo "Restoring from backup: $backup_file"

    # Create temporary directory
    mkdir -p "$TEMP_DIR"

    # Extract backup
    echo "Extracting backup..."
    unzip "$backup_file" -d "$TEMP_DIR"

    # Verify backup contents and determine format
    if [ -f "$TEMP_DIR/dump.backup" ]; then
        echo "Found backup in custom format (dump.backup)"
        DUMP_FILE="dump.backup"
        IS_CUSTOM_FORMAT=true
        
        echo "Analyzing dump file to detect database properties..."
        local detected_db_name=""
        if command -v strings >/dev/null 2>&1; then
            if strings "$TEMP_DIR/$DUMP_FILE" | grep -q "postgres_[a-zA-Z0-9_-]*"; then
                detected_db_name=$(strings "$TEMP_DIR/$DUMP_FILE" | grep -m1 "postgres_[a-zA-Z0-9_-]*" | grep -o "postgres_[a-zA-Z0-9_-]*" | head -1)
                echo "Detected database name from dump: $detected_db_name"
            elif strings "$TEMP_DIR/$DUMP_FILE" | grep -q "@.*-.*\.odoo\.com"; then
                detected_db_name=$(strings "$TEMP_DIR/$DUMP_FILE" | grep -m1 "@.*-.*\.odoo\.com" | sed -E 's/.*@[^-]+-([^.]+)\.odoo\.com.*/postgres_\1/')
                echo "Detected database name from email domain in dump: $detected_db_name"
            fi
        fi
    elif [ -f "$TEMP_DIR/dump.sql" ]; then
        echo "Found backup in SQL format (dump.sql)"
        DUMP_FILE="dump.sql"
        IS_CUSTOM_FORMAT=false

        echo "Analyzing dump file to detect database properties..."
        local detected_db_name=""
        if grep -q "postgres_[a-zA-Z0-9_-]*" "$TEMP_DIR/$DUMP_FILE"; then
            detected_db_name=$(grep -m1 "postgres_[a-zA-Z0-9_-]*" "$TEMP_DIR/$DUMP_FILE" | grep -o "postgres_[a-zA-Z0-9_-]*" | head -1)
            echo "Detected database name from dump: $detected_db_name"
        elif grep -q "@.*-.*\.odoo\.com" "$TEMP_DIR/$DUMP_FILE"; then
            detected_db_name=$(grep -m1 "@.*-.*\.odoo\.com" "$TEMP_DIR/$DUMP_FILE" | sed -E 's/.*@[^-]+-([^.]+)\.odoo\.com.*/postgres_\1/')
            echo "Detected database name from email domain in dump: $detected_db_name"
        fi
    else
        echo "Error: Invalid backup format. Missing dump.backup or dump.sql file"
        rm -rf "$TEMP_DIR"
        exit 1
    fi

    DETECTED_DB_NAME="$detected_db_name"

    if [ ! -d "$TEMP_DIR/filestore" ]; then
        echo "Error: Invalid backup format. Missing filestore directory"
        rm -rf "$TEMP_DIR"
        exit 1
    fi

    # Change to INSTALL_DIR for docker-compose commands
    cd "$INSTALL_DIR"

    if [ -n "$DETECTED_DB_NAME" ] && [ "$DETECTED_DB_NAME" != "$DB_NAME" ]; then
        echo "Warning: Detected database name ($DETECTED_DB_NAME) does not match current configuration ($DB_NAME)"
        echo "Updating configuration files to match the database dump..."

        local detected_client_name=$(echo "$DETECTED_DB_NAME" | sed -E 's/postgres_(.+)/\1/')

        echo "Updating docker-compose.yml..."
        sed -i "s/container_name: odoo17-[a-zA-Z0-9_-]*/container_name: odoo17-$detected_client_name/" docker-compose.yml
        sed -i "s/container_name: db-[a-zA-Z0-9_-]*/container_name: db-$detected_client_name/" docker-compose.yml
        sed -i "s/POSTGRES_DB=postgres_[a-zA-Z0-9_-]*/POSTGRES_DB=$DETECTED_DB_NAME/" docker-compose.yml
        sed -i "s/command: -- --init=base -d postgres_[a-zA-Z0-9_-]*/command: -- --init=base -d $DETECTED_DB_NAME/" docker-compose.yml 2>/dev/null || true

        echo "Updating odoo.conf..."
        sed -i "s/db_name = postgres_[a-zA-Z0-9_-]*/db_name = $DETECTED_DB_NAME/" config/odoo.conf 2>/dev/null || true

        echo "Updating backup.sh script variables and file..."

        CONTAINER_NAME="odoo17-$detected_client_name"
        DB_CONTAINER="db-$detected_client_name"
        DB_NAME="$DETECTED_DB_NAME"

        local temp_backup_script=$(mktemp)
        cat backup.sh | \
            sed "s/CONTAINER_NAME=\"odoo17-[a-zA-Z0-9_-]*\"/CONTAINER_NAME=\"odoo17-$detected_client_name\"/" | \
            sed "s/DB_CONTAINER=\"db-[a-zA-Z0-9_-]*\"/DB_CONTAINER=\"db-$detected_client_name\"/" | \
            sed "s/DB_NAME=\"postgres_[a-zA-Z0-9_-]*\"/DB_NAME=\"$DETECTED_DB_NAME\"/" > "$temp_backup_script"
        cat "$temp_backup_script" > backup.sh
        rm "$temp_backup_script"

        echo "Configuration files updated successfully."
    fi

    # Stop containers
    echo "Stopping services..."
    docker stop $CONTAINER_NAME $DB_CONTAINER || true
    docker rm $CONTAINER_NAME $DB_CONTAINER || true

    # Start database container
    echo "Starting database..."
    cd "$INSTALL_DIR"
    docker run -d --name $DB_CONTAINER \
        -e POSTGRES_DB=$DB_NAME \
        -e POSTGRES_PASSWORD={client_password} \
        -e POSTGRES_USER=$DB_USER \
        -e PGDATA=/var/lib/postgresql/data/pgdata \
        -v "$INSTALL_DIR/volumes/postgres-data:/var/lib/postgresql/data/pgdata" \
        postgres:15
    sleep 10

    # Recreate database
    echo "Recreating database..."
    docker exec $DB_CONTAINER psql -U $DB_USER postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$DB_NAME';"
    docker exec $DB_CONTAINER psql -U $DB_USER postgres -c "DROP DATABASE IF EXISTS $DB_NAME;"
    docker exec $DB_CONTAINER psql -U $DB_USER postgres -c "CREATE DATABASE $DB_NAME;"

    # Restore database based on format
    echo "Restoring database..."
    if [ "$IS_CUSTOM_FORMAT" = true ]; then
        cat "$TEMP_DIR/$DUMP_FILE" | docker exec -i $DB_CONTAINER pg_restore -U $DB_USER -d $DB_NAME --no-owner --role=$DB_USER
    else
        cat "$TEMP_DIR/$DUMP_FILE" | docker exec -i $DB_CONTAINER psql -U $DB_USER $DB_NAME
    fi

    # Restore filestore directly to volume
    echo "Restoring filestore..."
    rm -rf "$INSTALL_DIR/volumes/odoo-data/filestore"
    mkdir -p "$INSTALL_DIR/volumes/odoo-data/filestore"
    if ! cp -a "$TEMP_DIR/filestore/." "$INSTALL_DIR/volumes/odoo-data/filestore/"; then
        echo "Filestore restore failed"
        exit 1
    fi

    # Update timestamps to reflect restore time
    echo "Updating filestore timestamps..."
    find "$INSTALL_DIR/volumes/odoo-data/filestore" -exec touch {} +

    # Start all services
    echo "Starting services..."
    cd "$INSTALL_DIR"
    docker run -d --name $CONTAINER_NAME \
        --link $DB_CONTAINER:db \
        -p 8069:8069 \
        -v "$INSTALL_DIR/config:/etc/odoo" \
        -v "$INSTALL_DIR/volumes/odoo-data:/var/lib/odoo" \
        -v "$INSTALL_DIR/enterprise:/mnt/enterprise" \
        -v "$INSTALL_DIR/addons:/mnt/extra-addons" \
        -v "$INSTALL_DIR/logs:/var/log/odoo" \
        -e HOST=db \
        -e PORT=5432 \
        -e USER=$DB_USER \
        -e PASSWORD={client_password} \
        -e PROXY_MODE=True \
        odoo:17.0 -- --init=base -d $DB_NAME

    # Wait for services to be ready
    echo "Waiting for services to start..."
    sleep 20

    # Return to original directory
    cd "$current_dir"

    # Cleanup
    rm -rf "$TEMP_DIR"

    # Verify restore
    if curl -s http://localhost:8069/web/database/selector | grep -q "$DB_NAME"; then
        echo "Restore verified successfully"
    else
        echo "Warning: Could not verify restore. Please check Odoo logs"
        docker-compose logs web
    fi
}

# Function to list available backups
list_backups() {
    local daily_count=0
    local monthly_count=0
    local backups=()

    echo "Available backups:"
    echo "-----------------"
    echo "Daily backups:"
    while IFS= read -r backup; do
        if [ -f "$backup" ]; then
            daily_count=$((daily_count + 1))
            backups+=("$backup")
            local size=$(du -h "$backup" | cut -f1)
            local date=$(date -r "$backup" "+%Y-%m-%d %H:%M:%S")
            echo "  $daily_count) $(basename "$backup") ($size) - $date"
        fi
    done < <(find "$BACKUP_DIR/daily" -maxdepth 1 -type f -name "backup_*.zip" -print0 | sort -z -r | tr '\0' '\n')

    echo -e "\nMonthly backups:"
    while IFS= read -r backup; do
        if [ -f "$backup" ]; then
            local count=$((daily_count + monthly_count + 1))
            monthly_count=$((monthly_count + 1))
            backups+=("$backup")
            local size=$(du -h "$backup" | cut -f1)
            local date=$(date -r "$backup" "+%Y-%m-%d %H:%M:%S")
            echo "  $count) $(basename "$backup") ($size) - $date"
        fi
    done < <(find "$BACKUP_DIR/monthly" -maxdepth 1 -type f -name "backup_*.zip" -print0 | sort -z -r | tr '\0' '\n')

    if [ $((daily_count + monthly_count)) -eq 0 ]; then
        echo "No backups found."
        exit 1
    fi

    echo -e "\nSelect a backup to restore (1-$((daily_count + monthly_count))) or 'q' to quit:"
    local selection
    while true; do
        read -r selection
        if [[ "$selection" == "q" ]]; then
            echo "Operation cancelled."
            exit 0
        elif [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le $((daily_count + monthly_count)) ]; then
            local selected_backup="${backups[$((selection-1))]}"
            echo -e "\nYou selected: $(basename "$selected_backup")"

            # Confirmation loop
            while true; do
                echo "Are you sure you want to restore this backup? ([Y]/n)"
                local confirm
                read -r confirm

                # Convert to lowercase for comparison
                confirm=$(echo "$confirm" | tr '[:upper:]' '[:lower:]')

                if [[ -z "$confirm" ]] || [[ "$confirm" == "y" ]] || [[ "$confirm" == "yes" ]]; then
                    restore_backup "$selected_backup"
                    break
                elif [[ "$confirm" == "n" ]] || [[ "$confirm" == "no" ]]; then
                    echo "Operation cancelled."
                    exit 0
                else
                    echo "Invalid option: $confirm"
                    continue
                fi
            done
            break
        else
            echo "Invalid selection. Please enter a number between 1 and $((daily_count + monthly_count)) or 'q' to quit:"
        fi
    done
}

# Main script
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
