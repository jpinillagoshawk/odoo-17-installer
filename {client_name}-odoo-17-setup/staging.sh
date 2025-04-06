#!/bin/bash

# Constants
INSTALL_DIR="/{client_name}-odoo-17"
STAGING_DIR="$INSTALL_DIR/staging"
SERVER_IP={ip}
BASE_PORT={odoo_port}
LONGPOLLING_PORT=8072
POSTGRES_PORT={db_port}
GIT_CONFIG_FILE="$INSTALL_DIR/.git_config"
MAIN_BRANCH="main"

is_git_enabled() {
    [ -f "$GIT_CONFIG_FILE" ]
}

load_git_config() {
    if [ -f "$GIT_CONFIG_FILE" ]; then
        source "$GIT_CONFIG_FILE"
        return 0
    else
        return 1
    fi
}

# Function to display usage
usage() {
    echo "Usage: $0 [action] [name]"
    echo "Actions:"
    echo "  create [name]  - Create a new staging environment (name optional)"
    echo "                   If git is enabled, will create a branch from main"
    echo "  list          - List all staging environments"
    echo "  start [name]  - Start a staging environment"
    echo "  stop [name]   - Stop a staging environment"
    echo "  delete [name] - Delete a staging environment"
    echo "                   If git is enabled, will delete the branch too"
    echo "  update [name] - Update a staging environment from production"
    echo "  cleanup [name] - Clean up staging environment(s)"
    echo "                  Use 'all' to remove all staging environments"
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
                echo "Cleaning up orphaned staging directory: $d"
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

copy_files() {
    local name=$1
    local source_dir=$INSTALL_DIR
    local target_dir="$STAGING_DIR/$name"
    
    echo "Copying files..."
    
    for item in config enterprise docker-compose.yml; do
        if [ -d "$source_dir/$item" ]; then
            echo "  Copying directory: $item"
            cp -r "$source_dir/$item" "$target_dir/"
        else
            echo "  Copying file: $item"
            cp "$source_dir/$item" "$target_dir/"
        fi
    done
    
    if is_git_enabled && [ -d "$source_dir/addons/.git" ]; then
        echo "  Setting up git-controlled addons..."
        
        mkdir -p "$target_dir/addons"
        
        cp -r "$source_dir/addons/." "$target_dir/addons/"
        
        local branch_name=""
        if [ -f "$target_dir/.git_branch" ]; then
            branch_name=$(cat "$target_dir/.git_branch")
            
            cd "$target_dir/addons"
            git checkout "$branch_name" >/dev/null 2>&1
        fi
    else
        if [ -d "$source_dir/addons" ]; then
            echo "  Copying directory: addons"
            cp -r "$source_dir/addons" "$target_dir/"
        fi
    fi
}

create_git_branch() {
    local name=$1
    local staging_dir="$STAGING_DIR/$name"
    
    if ! is_git_enabled; then
        return 0
    fi
    
    load_git_config
    
    echo "Checking git repository status..."
    
    cd "$INSTALL_DIR/addons"
    
    if [ ! -d ".git" ]; then
        echo "Warning: addons directory is not a git repository. Skipping branch creation."
        return 1
    fi
    
    local current_branch=$(git rev-parse --abbrev-ref HEAD)
    
    git fetch origin $MAIN_BRANCH
    git checkout $MAIN_BRANCH
    git pull origin $MAIN_BRANCH
    
    local branch_name="staging-$name"
    
    if ! git show-ref --verify --quiet "refs/heads/$branch_name"; then
        echo "Creating git branch '$branch_name' from '$MAIN_BRANCH'..."
        git checkout -b "$branch_name" "$MAIN_BRANCH"
    else
        echo "Branch '$branch_name' already exists, checking it out..."
        git checkout "$branch_name"
    fi
    
    mkdir -p "$staging_dir"
    echo "$branch_name" > "$staging_dir/.git_branch"
    
    git checkout "$current_branch"
    
    echo "Git branch '$branch_name' created and associated with staging environment '$name'"
    return 0
}

# Function to create staging
create_staging() {
    local name=$1
    local num
    
    # Get next number if no name provided
    if [ -z "$name" ]; then
        num=$(get_next_number)
        name=$(get_staging_name "$num")
    else
        if [ "$name" = "staging" ]; then
            num=1
        else
            num=$(echo "$name" | grep -o '[0-9]*$')
            if [ -z "$num" ]; then
                echo "Error: Invalid staging name format"
                exit 1
            fi
        fi
    fi
    
    # Check if exists
    if [ -d "$STAGING_DIR/$name" ]; then
        echo "Error: Staging '$name' already exists"
        exit 1
    fi
    
    # Get web port
    local web_port
    web_port=$(get_ports "$num")
    if [ $? -ne 0 ]; then
        echo "$web_port"
        exit 1
    fi
    
    echo "Allocated port:"
    echo "  Web: $web_port"
    
    # Create directory structure
    echo "Creating staging environment '$name'..."
    mkdir -p "$STAGING_DIR/$name"
    
    copy_files "$name"
    
    # Update odoo.conf
    echo "Configuring odoo.conf..."
    local config_file="$STAGING_DIR/$name/config/odoo.conf"
    sed -i "s/^db_name =.*/db_name = postgres_{client_name}_$name/" "$config_file"
    
    # Update docker-compose.yml
    echo "Configuring docker-compose.yml..."
    local compose_file="$STAGING_DIR/$name/docker-compose.yml"
    
    # Create a temporary file
    local temp_file=$(mktemp)
    
    # Process the file line by line with proper structure
    while IFS= read -r line; do
        if [[ $line =~ .*"0.0.0.0:"[0-9]+":8069".* ]]; then
            # Map web port
            echo "      - \"0.0.0.0:$web_port:8069\"" >> "$temp_file"
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
    echo "Creating volume directories..."
    mkdir -p "$STAGING_DIR/$name/volumes/odoo-data"
    mkdir -p "$STAGING_DIR/$name/volumes/odoo-data/sessions"
    mkdir -p "$STAGING_DIR/$name/volumes/odoo-data/filestore"
    mkdir -p "$STAGING_DIR/$name/volumes/postgres-data"
    mkdir -p "$STAGING_DIR/$name/logs"
    
    # Set proper permissions
    echo "Setting directory permissions..."
    chown -R 101:101 "$STAGING_DIR/$name/volumes/odoo-data"
    chown -R 999:999 "$STAGING_DIR/$name/volumes/postgres-data"
    chmod -R 777 "$STAGING_DIR/$name/volumes/odoo-data"
    chmod -R 777 "$STAGING_DIR/$name/volumes/postgres-data"
    
    echo "Starting PostgreSQL container..."
    cd "$STAGING_DIR/$name"
    if ! docker-compose up -d db; then
        echo "Error: Failed to start PostgreSQL container"
        exit 1
    fi
    
    echo "Waiting for PostgreSQL to start..."
    sleep 10
    
    # Clone production database
    echo "Cloning production database..."
    
    # Stop Odoo container to ensure consistent backup
    echo "  Stopping production Odoo for consistent backup..."
    docker stop odoo17-{client_name}
    
    # Copy filestore with proper database name
    echo "  Copying filestore..."
    mkdir -p "$STAGING_DIR/$name/volumes/odoo-data/filestore/postgres_{client_name}_$name"
    if ! docker cp "odoo17-{client_name}:/var/lib/odoo/filestore/postgres_{client_name}/." \
        "$STAGING_DIR/$name/volumes/odoo-data/filestore/postgres_{client_name}_$name/"; then
        echo "Error: Failed to copy filestore"
        docker start odoo17-{client_name}
        exit 1
    fi
    
    # Reapply permissions after filestore copy
    chown -R 101:101 "$STAGING_DIR/$name/volumes/odoo-data"
    chmod -R 777 "$STAGING_DIR/$name/volumes/odoo-data"
    
    # Simple direct database clone
    echo "  Creating staging database..."
    # First drop the database if it exists (outside transaction)
    docker exec db-{client_name}-$name psql -U odoo -d template1 -q -c "DROP DATABASE IF EXISTS postgres_{client_name}_$name;" 2>/dev/null
    # Create empty database
    docker exec db-{client_name}-$name psql -U odoo -d template1 -q -c "CREATE DATABASE postgres_{client_name}_$name WITH TEMPLATE template0 OWNER odoo LC_COLLATE 'en_US.UTF-8' LC_CTYPE 'en_US.UTF-8';" 2>/dev/null
    
    # Now dump and restore
    echo "  Restoring database (this may take a while)..."
    if ! docker exec db-{client_name} pg_dump -U odoo -Fc -Z0 postgres_{client_name} > "/tmp/odoo_staging_$$.dump"; then
        echo "Error: Failed to dump database"
        docker start odoo17-{client_name}
        rm -f "/tmp/odoo_staging_$$.dump"
        exit 1
    fi
    
    if ! docker exec -i db-{client_name}-$name pg_restore -U odoo -d postgres_{client_name}_$name --no-owner --no-privileges --clean --if-exists < "/tmp/odoo_staging_$$.dump" 2>/dev/null; then
        echo "Warning: Some non-critical errors occurred during restore"
    fi
    rm -f "/tmp/odoo_staging_$$.dump"
    
    # Verify database was restored properly
    if ! docker exec db-{client_name}-$name psql -U odoo -d postgres_{client_name}_$name -q -t -c "SELECT COUNT(*) FROM res_users;" 2>/dev/null | grep -q '[1-9]'; then
        echo "Error: Database restore failed - database appears empty"
        docker start odoo17-{client_name}
        exit 1
    fi
    
    # Restart production Odoo
    echo "  Restarting production Odoo..."
    docker start odoo17-{client_name}

    # Start Odoo service first
    echo "Starting Odoo service..."
    cd "$STAGING_DIR/$name"
    docker-compose up -d web

    echo "Waiting for initial startup..."
    sleep 10

    # Now neutralize the database
    echo "  Neutralizing database..."
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
    echo "  Installing ribbon module..."
    docker exec odoo17-{client_name}-$name odoo -d postgres_{client_name}_$name -i web_environment_ribbon --stop-after-init >/dev/null 2>&1

    # Configure ribbon after installation
    echo "  Configuring ribbon..."
    docker exec db-{client_name}-staging psql -U odoo -d postgres_{client_name}_$name -c "UPDATE ir_config_parameter 
SET value = REPEAT('=', (23 - LENGTH('$name'))/2+1) || '⚠️ ' || UPPER('$name') || ' ⚠️.. NOT FOR PRODUCTION' || REPEAT('=', (23 - LENGTH('$name'))/2)
WHERE key = 'ribbon.name';" >/dev/null 2>&1

    # Update module to apply configuration
    echo "  Update ribbon module..."
    docker exec odoo17-{client_name}-$name odoo -d postgres_{client_name}_$name -u web_environment_ribbon --stop-after-init >/dev/null 2>&1

    # Restart to ensure clean state
    echo "Restarting service..."
    docker-compose restart web
    sleep 5

    create_git_branch "$name"

    echo "Staging environment created successfully:"
    echo "  Path: $STAGING_DIR/$name"
    echo "  Web port: $web_port (http://localhost:$web_port)"
    echo "  Database: postgres_{client_name}_$name"
    echo "  Status: Running"
}

# Function to list stagings
list_stagings() {
    echo "Existing staging environments:"
    echo "---------------------------------"
    
    for d in "$STAGING_DIR"/staging*; do
        if [ -d "$d" ]; then
            name=$(basename "$d")
            echo "Name: $name"
            
            # Get container status
            if docker ps -q --filter "name=odoo17-{client_name}-$name" | grep -q .; then
                echo "Status: Running"
            else
                echo "Status: Stopped"
            fi
            
            # Get port
            if [ -f "$d/docker-compose.yml" ]; then
                port=$(grep -o ":[0-9]*\":$BASE_PORT" "$d/docker-compose.yml" | cut -d':' -f2)
                echo "Web Port: ${port%\":$BASE_PORT\"}"
            fi
            
            echo "Path: $d"
            echo "---------------------------------"
        fi
    done
}

# Function to start staging
start_staging() {
    local name=$1
    if [ ! -d "$STAGING_DIR/$name" ]; then
        echo "Error: Staging '$name' does not exist"
        exit 1
    fi
    
    echo "Starting staging '$name'..."
    cd "$STAGING_DIR/$name" || exit 1
    docker-compose up -d
    
    # Get port
    port=$(grep -o ":[0-9]*\":$BASE_PORT" docker-compose.yml | cut -d':' -f2)
    port=${port%\":$BASE_PORT\"}
    
    echo "Waiting for services to start..."
    sleep 10
    
    # Check service
    max_attempts=30
    attempt=1
    while [ $attempt -le $max_attempts ]; do
        if curl -s "http://localhost:$port/web/database/selector" > /dev/null; then
            echo "Staging '$name' started successfully"
            echo "Access at: http://localhost:$port"
            exit 0
        fi
        echo "Waiting for Odoo to start (attempt $attempt/$max_attempts)..."
        sleep 2
        attempt=$((attempt + 1))
    done
    
    echo "Warning: Odoo web interface not responding, but containers are running"
}

# Function to stop staging
stop_staging() {
    local name=$1
    if [ ! -d "$STAGING_DIR/$name" ]; then
        echo "Error: Staging '$name' does not exist"
        exit 1
    fi
    
    echo "Stopping staging '$name'..."
    cd "$STAGING_DIR/$name" || exit 1
    docker-compose down
    echo "Staging '$name' stopped successfully"
}

delete_git_branch() {
    local name=$1
    
    if ! is_git_enabled; then
        return 0
    fi
    
    load_git_config
    
    if [ ! -f "$STAGING_DIR/$name/.git_branch" ]; then
        echo "No git branch found for staging '$name'"
        return 1
    fi
    
    local branch_name=$(cat "$STAGING_DIR/$name/.git_branch")
    
    echo "Deleting git branch '$branch_name'..."
    
    cd "$INSTALL_DIR/addons"
    
    git checkout $MAIN_BRANCH
    
    git branch -D "$branch_name" 2>/dev/null || echo "Warning: Could not delete local branch"
    
    return 0
}

# Function to delete staging
delete_staging() {
    local name=$1
    if [ ! -d "$STAGING_DIR/$name" ]; then
        echo "Error: Staging '$name' does not exist"
        exit 1
    fi
    
    # Stop first
    stop_staging "$name"
    
    if is_git_enabled && [ -f "$STAGING_DIR/$name/.git_branch" ]; then
        local branch_name=$(cat "$STAGING_DIR/$name/.git_branch")
        cd "$INSTALL_DIR/addons"
        
        git checkout "$branch_name" 2>/dev/null
        if ! git diff-index --quiet HEAD --; then
            echo "Warning: There are uncommitted changes in branch '$branch_name'"
            echo "These changes will be lost if you continue."
            read -p "Continue with deletion? (y/N): " confirm
            if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
                echo "Deletion cancelled."
                git checkout $MAIN_BRANCH
                return 1
            fi
        fi
        git checkout $MAIN_BRANCH
    fi
    
    delete_git_branch "$name"
    
    # Remove directory
    echo "Deleting staging '$name'..."
    rm -rf "$STAGING_DIR/$name"
    echo "Staging '$name' deleted successfully"
}

# Function to update staging
update_staging() {
    local name=$1
    if [ ! -d "$STAGING_DIR/$name" ]; then
        echo "Error: Staging '$name' does not exist"
        exit 1
    fi
    
    echo "Updating staging '$name'..."
    
    # Stop containers
    stop_staging "$name"
    
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
    for item in config enterprise addons docker-compose.yml; do
        if [ -d "$INSTALL_DIR/$item" ]; then
            rm -rf "$STAGING_DIR/$name/$item"
            cp -r "$INSTALL_DIR/$item" "$STAGING_DIR/$name/"
        else
            cp -f "$INSTALL_DIR/$item" "$STAGING_DIR/$name/"
        fi
    done
    
    # Update docker-compose.yml with original ports
    sed -i "s/:$BASE_PORT\"/:$web_port\"/g" "$compose_file"
    sed -i "s/:$LONGPOLLING_PORT\"/:$long_port\"/g" "$compose_file"
    sed -i "s/:$POSTGRES_PORT\"/:$pg_port\"/g" "$compose_file"
    sed -i "s/container_name: odoo17-{client_name}/container_name: odoo17-{client_name}-$name/g" "$compose_file"
    sed -i "s/container_name: db-{client_name}/container_name: db-{client_name}-$name/g" "$compose_file"
    sed -i "s/POSTGRES_DB=postgres_{client_name}/POSTGRES_DB=postgres_{client_name}_$name/g" "$compose_file"
    
    # Update base URL and report URL
    docker exec db-{client_name}-$name psql -U odoo postgres_{client_name}_$name << EOF
BEGIN;

-- Update base URL and report URL
UPDATE ir_config_parameter SET value = 'http://$SERVER_IP:$BASE_PORT' WHERE key = 'web.base.url';
UPDATE ir_config_parameter SET value = 'http://localhost:$BASE_PORT' WHERE key = 'report.url';
INSERT INTO ir_config_parameter (key, value)
SELECT 'report.url', 'http://localhost:$BASE_PORT'
WHERE NOT EXISTS (SELECT 1 FROM ir_config_parameter WHERE key = 'report.url');

COMMIT;
EOF

    # Sync filestore
    echo "Syncing filestore..."
    docker stop odoo17-{client_name}
    
    # Clear and recreate filestore directory for clean sync
    rm -rf "$STAGING_DIR/$name/volumes/odoo-data/filestore/postgres_{client_name}_$name"
    mkdir -p "$STAGING_DIR/$name/volumes/odoo-data/filestore/postgres_{client_name}_$name"
    
    # Copy updated filestore
    if ! docker cp "odoo17-{client_name}:/var/lib/odoo/filestore/postgres_{client_name}/." \
        "$STAGING_DIR/$name/volumes/odoo-data/filestore/postgres_{client_name}_$name/"; then
        echo "Warning: Failed to sync filestore"
    fi
    
    docker start odoo17-{client_name}
    
    # Reapply all permissions (matching install.sh)
    chown -R 101:101 "$STAGING_DIR/$name/volumes/odoo-data"
    chown -R 999:999 "$STAGING_DIR/$name/volumes/postgres-data"
    chmod -R 777 "$STAGING_DIR/$name/volumes/odoo-data"
    chmod -R 777 "$STAGING_DIR/$name/volumes/postgres-data"
    
    # Start containers
    start_staging "$name"
}

# Function to cleanup staging
cleanup_staging() {
    local name=$1
    
    if [ "$name" = "all" ]; then
        echo "Cleaning up all staging environments..."
        
        # Stop and remove all staging containers
        echo "Stopping and removing staging containers..."
        if docker ps -a | grep -q "{client_name}-staging"; then
            docker ps -a | grep "{client_name}-staging" | awk '{print $1}' | xargs -r docker rm -f
        else
            echo "No staging containers found."
        fi
        
        # Remove staging volumes
        echo "Removing staging volumes..."
        if docker volume ls | grep -q "staging"; then
            docker volume ls | grep "staging" | awk '{print $2}' | xargs -r docker volume rm
        else
            echo "No staging volumes found."
        fi
        
        # Remove staging networks
        echo "Removing staging networks..."
        if docker network ls | grep -q "staging"; then
            docker network ls | grep "staging" | awk '{print $1}' | xargs -r docker network rm
        else
            echo "No staging networks found."
        fi
        
        # Remove all staging directories
        echo "Removing staging directories..."
        if [ -d "$STAGING_DIR" ] && [ -n "$(ls -A $STAGING_DIR)" ]; then
            rm -rf "$STAGING_DIR"/*
            echo "All staging directories removed."
        else
            echo "No staging directories found."
        fi
        
        echo "All staging environments have been cleaned up successfully!"
        
    else
        # Verify staging exists
        if [ ! -d "$STAGING_DIR/$name" ]; then
            echo "Error: Staging '$name' does not exist"
            exit 1
        fi
        
        echo "Cleaning up staging environment '$name'..."
        
        # Stop and remove containers
        echo "Stopping and removing containers..."
        if docker ps -a | grep -q "{client_name}-$name\$"; then
            docker ps -a | grep "{client_name}-$name\$" | awk '{print $1}' | xargs -r docker rm -f
        else
            echo "No containers found for staging '$name'."
        fi
        
        # Remove volumes
        echo "Removing volumes..."
        if docker volume ls | grep -q "_$name\$"; then
            docker volume ls | grep "_$name\$" | awk '{print $2}' | xargs -r docker volume rm
        else
            echo "No volumes found for staging '$name'."
        fi
        
        # Remove network
        echo "Removing network..."
        if docker network ls | grep -q "_$name\$"; then
            docker network ls | grep "_$name\$" | awk '{print $1}' | xargs -r docker network rm
        else
            echo "No network found for staging '$name'."
        fi
        
        # Remove directory
        echo "Removing staging directory..."
        rm -rf "$STAGING_DIR/$name"
        
        echo "Staging environment '$name' has been cleaned up successfully!"
    fi
}

# Main script
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