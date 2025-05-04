#!/bin/bash

# Odoo 17 Installation Script for {client_name}
# Created: $(date)

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
INSTALL_DIR="{install_dir}"
TEMP_LOG="/tmp/odoo_install.log"
LOG_FILE="$INSTALL_DIR/logs/install.log"
ODOO_ENTERPRISE_DEB="{path_to_install}/odoo_17.0+e.latest_all.deb"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
SETUP_DIR=$(dirname "$0")

# Database and authentication constants
DB_NAME="{odoo_db_name}"
DB_USER="{db_user}"
DB_PASS="{client_password}"
ADMIN_PASS="{client_password}"
ODOO_CONTAINER_NAME="{odoo_container_name}"
DB_CONTAINER="{db_container_name}"
PUBLIC_IP="{ip}"
ODOO_PORT="{odoo_port}"
DB_PORT="{db_port}"

# Display banner
show_banner() {
    echo -e "${BG_BLUE}${WHITE}${BOLD}"
    echo "  ___                          ___    ___   " && \
    echo " / _ \      _                 /   |  / _ \\ " && \
    echo "| | | |  __| |  ___    ___   /_/| | | (_) | " && \
    echo "| | | | / _\` | / _ \  / _ \     | | |  _  | " && \
    echo "| |_| || (_| || (_) || (_) |    | | | (_) | " && \
    echo " \___/  \__,_| \___/  \___/     |_|  \\___/ " && \
    echo "                                            " && \
    echo -e "${RESET}"
    echo -e "${CYAN}${BOLD}Installation Script for {client_name}${RESET}"
    echo -e "${YELLOW}Property of Azor Data SL (Spain)${RESET}"
    echo -e "${DIM}Created: $(date)${RESET}"

    
    echo
}

# Logging function with timestamp and colors
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

    # Fix output formatting - ensure proper line endings for all platforms
    printf "${level_color}[%s] [%s]${RESET} %s\n" "$TIMESTAMP" "$level" "$*" | tee -a "$TEMP_LOG"
}

# Error handling
set -e
trap 'cleanup_on_error' ERR

# Cleanup function for error handling
cleanup_on_error() {
    echo -e "${BG_RED}${WHITE}${BOLD}"
    echo " _____   _____   _____    ___    _____  "
    echo "|  ___| |  _  \ |  _  \  / _ \  |  _  \ "
    echo "| |__   | |_| | | |_| | | | | | | |_| | "
    echo "|  __|  |  _  / |  _  / | | | | |  _  /  "
    echo "| |___  | | \ \ | | \ \ | |_| | | | \ \  "
    echo "|_____| |_|  \_\\|_|  \_\\ \\___/  |_|  \_\ "
    echo -e "${RESET}"
    
    log ERROR "Installation failed, cleaning up..."
    cd "$INSTALL_DIR"
    
    # Stop and remove containers
    docker compose down -v 2>/dev/null || true
    
    # Clean up directories
    rm -rf "$INSTALL_DIR/volumes"/* 2>/dev/null || true
    
    log ERROR "Cleanup completed"
    echo -e "${RED}${BOLD}Please check the log file at ${UNDERLINE}$LOG_FILE${RESET}${RED}${BOLD} for details${RESET}"
    exit 1
}

# Display cleanup message
display_cleanup_message() {
    echo ""
    echo -e "${GREEN}${BOLD}===== INSTALLATION COMPLETED =====${RESET}"
    echo -e "${CYAN}The installation has been completed successfully.${RESET}"
    echo -e "All necessary files have been copied to ${YELLOW}$INSTALL_DIR${RESET}."
    echo ""
    echo -e "You can now safely remove the setup directory if needed:"
    echo -e "${DIM}rm -rf $SETUP_PATH${RESET}"
    echo ""
    echo -e "${CYAN}${BOLD}To manage Odoo, use the following commands:${RESET}"
    echo -e "${DIM}cd $INSTALL_DIR && docker compose <command>${RESET}"
    echo ""
    echo -e "For example:"
    echo -e "${YELLOW}cd $INSTALL_DIR && docker compose down${RESET}    # Stop Odoo"
    echo -e "${YELLOW}cd $INSTALL_DIR && docker compose up -d${RESET}   # Start Odoo"
    echo -e "${YELLOW}cd $INSTALL_DIR && docker compose logs -f${RESET} # View logs"
    echo ""
    echo -e "${GREEN}${BOLD}Odoo is now accessible at ${UNDERLINE}http://$PUBLIC_IP:$ODOO_PORT${RESET}"
    echo -e "${CYAN}Database: ${BOLD}$DB_NAME${RESET}"
    echo -e "${CYAN}Username: ${BOLD}admin${RESET}"
    echo -e "${CYAN}Password: ${BOLD}$ADMIN_PASS${RESET}"
    echo ""
    echo -e "${YELLOW}Property of Azor Data SL (Spain)${RESET}"
}

# Validation function
validate() {
    local what=$1
    local check_cmd=$2
    local error_msg=$3
    
    log INFO "Validating $what..."
    if ! eval "$check_cmd"; then
        log ERROR "$error_msg"
        exit 1
    fi
    log INFO "$what validation successful"
}

# Set correct permissions based on OS
set_permissions() {
    local target_dir=$1
    
    # Detect OS type if not already done
    if [ -z "$IS_WINDOWS" ]; then
        IS_WINDOWS=false
        if [[ "$(uname -s)" == *"MINGW"* ]] || [[ "$(uname -s)" == *"MSYS"* ]] || [[ "$(uname -s)" == *"CYGWIN"* ]]; then
            IS_WINDOWS=true
        fi
    fi
    
    if [ "$IS_WINDOWS" = "true" ]; then
        log INFO "Skipping Unix permissions on Windows for $target_dir"
        # For Windows, we only use chmod for executable scripts
        if [[ "$target_dir" == *".sh" ]]; then
            chmod +x "$target_dir" 2>/dev/null || log WARNING "Could not set executable permission for $target_dir"
        fi
    else
        # Full Unix permissions handling for Linux/macOS
        if [ -d "$target_dir" ]; then
            # Directory permissions
            log INFO "Setting permissions for directory: $target_dir"
            chmod -R 755 "$target_dir" 2>/dev/null || log WARNING "Could not set permissions for $target_dir"
            chown -R 101:101 "$target_dir" 2>/dev/null || log WARNING "Could not set ownership for $target_dir"
        elif [ -f "$target_dir" ]; then
            # File permissions
            log INFO "Setting permissions for file: $target_dir"
            if [[ "$target_dir" == *".sh" ]]; then
                # Executable script
                chmod 755 "$target_dir" 2>/dev/null || log WARNING "Could not set permissions for $target_dir"
            else
                # Regular file
                chmod 644 "$target_dir" 2>/dev/null || log WARNING "Could not set permissions for $target_dir"
            fi
            chown 101:101 "$target_dir" 2>/dev/null || log WARNING "Could not set ownership for $target_dir"
        fi
    fi
}

# Create directory structure
create_directories() {
    log INFO "Creating directory structure..."
    
    # Create all required directories with proper structure
    for dir in \
        config \
        volumes/odoo-data/{.local,filestore,sessions} \
        volumes/postgres-data \
        backups/{daily,monthly} \
        logs \
        enterprise \
        addons; do
        mkdir -p "$INSTALL_DIR/$dir"
        validate "$INSTALL_DIR/$dir directory" "[ -d '$INSTALL_DIR/$dir' ]" "Failed to create directory: $INSTALL_DIR/$dir"
    done
    
    # Set correct ownership and permissions
    # 101:101 is the UID:GID for the odoo user inside the container
    log INFO "Setting permissions for Odoo directories..."
    set_permissions "$INSTALL_DIR/volumes/odoo-data"
    set_permissions "$INSTALL_DIR/volumes/postgres-data"
    set_permissions "$INSTALL_DIR/logs"
    
    # Ensure sessions directory has correct permissions
    log INFO "Ensuring sessions directory has correct permissions..."
    set_permissions "$INSTALL_DIR/volumes/odoo-data/sessions"
    
    # Move temporary log to final location
    mv "$TEMP_LOG" "$LOG_FILE" 2>/dev/null || true
    log INFO "Directory structure created successfully"
}

# Check prerequisites
check_prerequisites() {
    log INFO "Checking prerequisites..."
    
    # Check Docker
    validate "Docker installation" "command -v docker" "Docker is not installed"
    log INFO "Docker is installed: $(docker --version)"
    
    # Check Docker Compose
    if command -v docker compose &>/dev/null; then
        log INFO "Docker Compose is installed (standalone)"
    elif docker compose version &>/dev/null; then
        log INFO "Docker Compose is installed (plugin)"
    else
        log ERROR "Docker Compose is not installed"
        exit 1
    fi
    
    # Detect OS type
    IS_WINDOWS=false
    if [[ "$(uname -s)" == *"MINGW"* ]] || [[ "$(uname -s)" == *"MSYS"* ]] || [[ "$(uname -s)" == *"CYGWIN"* ]]; then
        IS_WINDOWS=true
        log INFO "Windows environment detected (Git Bash/MSYS2/Cygwin)"
    fi
    
    # Check if Docker is actually accessible, which is what really matters
    if docker info &>/dev/null; then
        log INFO "Docker is accessible. Permission check passed."
        DOCKER_ACCESSIBLE=true
    else
        DOCKER_ACCESSIBLE=false
        log WARNING "Docker is installed but not accessible by current user."
    fi

    # On Windows, group membership check is unreliable in Git Bash, so we focus on Docker accessibility
    if [ "$IS_WINDOWS" = "true" ]; then
        if [ "$DOCKER_ACCESSIBLE" = "true" ]; then
            log INFO "Docker is accessible. Skipping Docker group check on Windows."
        else
            # Docker is not accessible on Windows
            log WARNING "Cannot access Docker on Windows. You may need to:"
            log ERROR "1. Open Command Prompt as Administrator"
            log ERROR "2. Run: net localgroup docker /add        # Create docker group if needed"
            log ERROR "3. Run: net localgroup docker %USERNAME% /add   # Add user to docker group"
            log ERROR "4. Make sure Docker Desktop is running (check system tray)"
            log ERROR "5. Log out of Windows and log back in"
            log ERROR "6. Run this script again"
            
            # Ask user if they want to continue anyway
            read -p "Do you want to continue anyway? (y/n): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log ERROR "Installation aborted by user."
                exit 1
            else
                log WARNING "Continuing despite Docker access issues. This may cause problems later."
            fi
        fi
    else
        # Linux/macOS path for checking group membership
        # Try multiple methods to check if user is in docker group
        if ! groups 2>/dev/null | grep -q docker && ! id -nG 2>/dev/null | grep -q docker; then
            log WARNING "Current user is not in docker group, attempting to add..."
            
            # Check if we have sudo and can use it
            if ! command -v sudo &>/dev/null; then
                log ERROR "The 'sudo' command is not available. You need administrative privileges to add the user to the docker group."
                log ERROR "Please manually run these commands as an administrative user:"
                log ERROR "1. groupadd docker               # Create docker group if it doesn't exist"
                log ERROR "2. usermod -aG docker $(whoami)  # Add current user to docker group"
                log ERROR "3. Log out and log back in, or run 'newgrp docker' to apply changes"
                exit 1
            fi
            
            # Check if docker group exists using multiple methods
            DOCKER_GROUP_EXISTS=false
            if command -v getent &>/dev/null && getent group docker &>/dev/null; then
                DOCKER_GROUP_EXISTS=true
            elif grep -q "^docker:" /etc/group 2>/dev/null; then
                DOCKER_GROUP_EXISTS=true
            elif cat /etc/group 2>/dev/null | grep -q "^docker:"; then
                DOCKER_GROUP_EXISTS=true
            fi
            
            # Create docker group if it doesn't exist
            if [ "$DOCKER_GROUP_EXISTS" = "false" ]; then
                log WARNING "Docker group does not exist, creating it..."
                sudo groupadd docker || {
                    log ERROR "Failed to create docker group. Please run: sudo groupadd docker"
                    exit 1
                }
            fi
            
            # Add user to docker group
            log WARNING "Adding user to docker group..."
            sudo usermod -aG docker $(whoami) || {
                log ERROR "Failed to add user to docker group. Please run: sudo usermod -aG docker $(whoami)"
                exit 1
            }
            
            log WARNING "User added to docker group. You need to log out and log back in for changes to take effect."
            log WARNING "Alternatively, try running: newgrp docker"
            
            # Try to apply group changes without requiring logout
            if command -v newgrp &>/dev/null; then
                log INFO "Attempting to apply group changes with newgrp..."
                # Save current script path for re-execution
                SCRIPT_PATH="$(readlink -f "$0")"
                # Prompt the user to run the script again after logging out/in or using newgrp
                log WARNING "Please run the script again after logging out and back in, or run:"
                log WARNING "newgrp docker && $SCRIPT_PATH"
                exit 0
            else
                log WARNING "The 'newgrp' command is not available. Please log out and log back in to apply changes."
                exit 1
            fi
        else
            log INFO "User appears to be in the docker group."
            
            # Double check if Docker is accessible
            if [ "$DOCKER_ACCESSIBLE" = "false" ]; then
                log WARNING "User is in docker group but can't access Docker. You may need to log out and log back in."
                # Ask user if they want to continue anyway
                read -p "Do you want to continue anyway? (y/n): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    log ERROR "Installation aborted by user."
                    exit 1
                else
                    log WARNING "Continuing despite Docker access issues. This may cause problems later."
                fi
            fi
        fi
    fi
    
    # Check port availability (use both netstat and ss if available)
    if command -v netstat &>/dev/null; then
        validate "Port $ODOO_PORT (netstat)" "! netstat -tuln 2>/dev/null | grep -q :$ODOO_PORT" "Port $ODOO_PORT is already in use"
    elif command -v ss &>/dev/null; then
        validate "Port $ODOO_PORT (ss)" "! ss -tuln 2>/dev/null | grep -q :$ODOO_PORT" "Port $ODOO_PORT is already in use"
    else
        log WARNING "Neither netstat nor ss commands are available to check port $ODOO_PORT availability"
        # Windows fallback for checking port
        if [ "$IS_WINDOWS" = "true" ] && command -v netstat &>/dev/null; then
            if netstat -ano | grep -q ":$ODOO_PORT"; then
                log ERROR "Port $ODOO_PORT is already in use"
                exit 1
            fi
        fi
    fi
}

# Extract enterprise addons
extract_enterprise() {
    log INFO "Extracting enterprise addons..."
    
    # For Windows systems, offer a simplified approach
    if [[ "$(uname -s)" == *"MINGW"* ]] || [[ "$(uname -s)" == *"MSYS"* ]] || [[ "$(uname -s)" == *"CYGWIN"* ]]; then
        log INFO "Windows system detected, using simplified enterprise addons setup..."
        
        # Display enterprise setup options
        echo -e "${YELLOW}${BOLD}Enterprise addons setup options:${RESET}"
        echo -e "${CYAN}1) Use an existing enterprise addons folder${RESET}"
        echo -e "${CYAN}2) Extract from a zip/rar file${RESET}"
        echo -e "${CYAN}3) Continue without enterprise addons${RESET}"
        echo -e "${CYAN}4) Abort installation${RESET}"
        
        local choice
        while true; do
            read -p "Enter your choice (1-4): " choice
            case $choice in
                1)
                    # Option 1: Use existing enterprise addons folder
                    local enterprise_path_raw
                    read -r -p "Enter the full path to your enterprise addons folder: " enterprise_path_raw
                    
                    # Handle Windows path conversion
                    enterprise_path=$(echo "$enterprise_path_raw" | tr '\\' '/')
                    if [[ "$enterprise_path" =~ ^[A-Za-z]: ]]; then
                        drive_letter=$(echo "${enterprise_path:0:1}" | tr '[:upper:]' '[:lower:]')
                        enterprise_path="/$(echo "$drive_letter")/${enterprise_path:2}"
                        # Clean up double slashes if present
                        enterprise_path=$(echo "$enterprise_path" | sed 's|//|/|g')
                    fi
                    
                    # Create Docker-compatible path for docker-compose.yml (/mnt/c/... format)
                    enterprise_path_docker_compose="${enterprise_path}"
                    
                    # Validate the path
                    if [ ! -d "$enterprise_path" ]; then
                        log ERROR "Directory not found: $enterprise_path"
                        continue
                    fi
                    
                    # Check if it contains enterprise modules
                    if [ ! -f "$enterprise_path/web_enterprise" ] && [ ! -d "$enterprise_path/web_enterprise" ]; then
                        log WARNING "The provided directory doesn't appear to contain enterprise modules (web_enterprise not found)"
                        read -p "Use this directory anyway? (y/n): " confirm
                        if [[ ! $confirm =~ ^[Yy]$ ]]; then
                            continue
                        fi
                    fi
                    
                    log INFO "Using existing enterprise addons at: $enterprise_path"
                    
                    # Update docker-compose.yml to use the external enterprise folder
                    log INFO "Updating docker-compose.yml to use external enterprise folder..."
                    
                    # First, create a backup of the original docker-compose.yml
                    cp "$SETUP_DIR/docker-compose.yml" "$SETUP_DIR/docker-compose.yml.bak"
                    
                    # Modify the docker-compose.yml with safer sed approach
                    sed -i "s|      - \./enterprise:/mnt/enterprise|      - ../odooV17/enterprise-17.0:/mnt/enterprise|g" "$SETUP_DIR/docker-compose.yml"
                    
                    # Create an empty enterprise directory for structure completeness
                    mkdir -p "$INSTALL_DIR/enterprise"
                    touch "$INSTALL_DIR/enterprise/README.txt"
                    echo "Enterprise addons are mounted from: $enterprise_path" > "$INSTALL_DIR/enterprise/README.txt"
                    
                    log SUCCESS "Docker configuration updated to use external enterprise addons"
                    return 0
                    ;;
                    
                2)
                    # Option 2: Extract from a zip file
                    local zip_path
                    read -r -p "Enter the path to folder containing enterprise zip file(s): " zip_path
                    
                    # Handle Windows path conversion
                    zip_path=$(echo "$zip_path" | tr '\\' '/')
                    if [[ "$zip_path" =~ ^[A-Za-z]: ]]; then
                        drive_letter=$(echo "${zip_path:0:1}" | tr '[:upper:]' '[:lower:]')
                        zip_path="/$(echo "$drive_letter")/${zip_path:2}"
                    fi
                    
                    # Validate the path
                    if [ ! -d "$zip_path" ]; then
                        log ERROR "Directory not found: $zip_path"
                        continue
                    fi
                    
                    # Find all zip/rar files in the directory
                    local archive_files=()
                    log INFO "Searching for archive files in: $zip_path"
                    
                    for ext in "*.zip" "*.rar" "*.7z"; do
                        while IFS= read -r -d '' file; do
                            archive_files+=("$file")
                        done < <(find "$zip_path" -maxdepth 1 -name "$ext" -type f -print0 2>/dev/null || find "$zip_path" -maxdepth 1 -name "$ext" -print0 2>/dev/null)
                        
                        # If no files found with find, try direct glob
                        if [ ${#archive_files[@]} -eq 0 ]; then
                            for file in "$zip_path"/$ext; do
                                if [ -f "$file" ] && [ "$file" != "$zip_path/$ext" ]; then
                                    archive_files+=("$file")
                                fi
                            done
                        fi
                    done
                    
                    # Check if any archive files were found
                    if [ ${#archive_files[@]} -eq 0 ]; then
                        log ERROR "No zip, rar, or 7z files found in: $zip_path"
                        continue
                    fi
                    
                    # If multiple archives found, let the user choose
                    local selected_archive
                    if [ ${#archive_files[@]} -eq 1 ]; then
                        selected_archive="${archive_files[0]}"
                        log INFO "Found archive file: $selected_archive"
                    else
                        log INFO "Multiple archive files found, please select one:"
                        for i in "${!archive_files[@]}"; do
                            echo -e "${CYAN}$((i+1))) ${archive_files[$i]}${RESET}"
                        done
                        
                        local file_choice
                        while true; do
                            read -p "Enter your choice (1-${#archive_files[@]}): " file_choice
                            if [[ "$file_choice" -ge 1 && "$file_choice" -le ${#archive_files[@]} ]]; then
                                selected_archive="${archive_files[$((file_choice-1))]}"
                                log INFO "Selected archive: $selected_archive"
                                break
                            else
                                log WARNING "Invalid choice, please enter a number between 1 and ${#archive_files[@]}"
                            fi
                        done
                    fi
                    
                    # Create enterprise directory
                    mkdir -p "$INSTALL_DIR/enterprise"
                    
                    # Extract archive using 7-Zip if available, otherwise try unzip
                    log INFO "Extracting enterprise archive to: $INSTALL_DIR/enterprise"
                    
                    local extract_success=false
                    
                    # Try 7-Zip first
                    for seven_zip in "/c/Program Files/7-Zip/7z.exe" "/c/Program Files (x86)/7-Zip/7z.exe" "7z.exe" "7z"; do
                        if [ -x "$seven_zip" ] || command -v "$seven_zip" >/dev/null 2>&1; then
                            log INFO "Using 7-Zip: $seven_zip"
                            if "$seven_zip" x -o"$INSTALL_DIR/enterprise" "$selected_archive" -y; then
                                extract_success=true
                                break
                            fi
                        fi
                    done
                    
                    # Try unzip if 7-Zip failed
                    if [ "$extract_success" != "true" ] && command -v unzip >/dev/null 2>&1; then
                        log INFO "Using unzip command"
                        if unzip -o "$selected_archive" -d "$INSTALL_DIR/enterprise"; then
                            extract_success=true
                        fi
                    fi
                    
                    # Try Windows explorer for extraction as last resort
                    if [ "$extract_success" != "true" ]; then
                        log WARNING "Automatic extraction failed. Please extract manually."
                        
                        # Convert paths to Windows format for display
                        local win_archive=$(echo "$selected_archive" | sed 's|^/\([a-z]\)/|\1:/|' | tr '/' '\\')
                        local win_target=$(echo "$INSTALL_DIR/enterprise" | sed 's|^/\([a-z]\)/|\1:/|' | tr '/' '\\')
                        
                        echo -e "${YELLOW}${BOLD}Please extract the archive manually:${RESET}"
                        echo -e "${CYAN}1) Open the archive file: ${win_archive}${RESET}"
                        echo -e "${CYAN}2) Extract all files to: ${win_target}${RESET}"
                        echo -e "${CYAN}3) Press Enter when done${RESET}"
                        
                        read -p "Press Enter after extraction (or type 'skip' to continue without enterprise): " manual_extract
                        
                        if [ "$manual_extract" = "skip" ]; then
                            log WARNING "Skipping enterprise addons extraction"
                        else
                            # Check if files were extracted
                            if [ -n "$(ls -A "$INSTALL_DIR/enterprise" 2>/dev/null)" ]; then
                                extract_success=true
                            else
                                log ERROR "No files found in enterprise directory after manual extraction"
                            fi
                        fi
                    fi
                    
                    # Validate the extracted content
                    if [ "$extract_success" = "true" ]; then
                        # Check for nested directories - if there's only one directory, use its contents
                        local dirs_count=$(find "$INSTALL_DIR/enterprise" -maxdepth 1 -type d | wc -l)
                        if [ "$dirs_count" -eq 2 ]; then  # 2 because the directory itself is counted
                            local subdir=$(find "$INSTALL_DIR/enterprise" -maxdepth 1 -type d -not -path "$INSTALL_DIR/enterprise")
                            log INFO "Found single subdirectory: $subdir, checking contents"
                            
                            # Check if it has typical enterprise module directories
                            if [ -d "$subdir/web_enterprise" ] || [ -d "$subdir/account_enterprise" ]; then
                                log INFO "Found enterprise modules in subdirectory, moving them up one level"
                                # Move all files from subdirectory to enterprise directory
                                mv "$subdir"/* "$INSTALL_DIR/enterprise/" 2>/dev/null
                                mv "$subdir"/.[!.]* "$INSTALL_DIR/enterprise/" 2>/dev/null || true  # Move hidden files too
                                rmdir "$subdir" 2>/dev/null || true
                            fi
                        fi
                        
                        log SUCCESS "Enterprise addons extraction completed successfully"
                        return 0
                    else
                        log ERROR "Failed to extract enterprise addons"
                        return 1
                    fi
                    ;;
                    
                3)
                    # Option 3: Continue without enterprise addons
                    log WARNING "Continuing installation without enterprise addons"
                    mkdir -p "$INSTALL_DIR/enterprise"
                    return 0
                    ;;
                
                4)
                    # Option 4: Abort installation
                    log ERROR "Installation aborted by user"
                    exit 1
                    ;;
                    
                *)
                    log WARNING "Invalid choice, please enter 1, 2, 3, or 4"
                    ;;
            esac
        done
    else
        # Non-Windows path (original implementation)
        # Check if enterprise DEB file exists
        if [ ! -f "$ODOO_ENTERPRISE_DEB" ]; then
            log WARNING "Enterprise DEB file not found at: $ODOO_ENTERPRISE_DEB"
            
            # Display menu for user options
            echo -e "${YELLOW}${BOLD}Enterprise addons file not found. Please choose an option:${RESET}"
            echo -e "${CYAN}1) Continue without enterprise addons${RESET}"
            echo -e "${CYAN}2) Specify the path to enterprise addons file or directory${RESET}"
            echo -e "${CYAN}3) Abort installation${RESET}"
            
            # Get user input
            local choice
            while true; do
                read -p "Enter your choice (1-3): " choice
                case $choice in
                    1)
                        log WARNING "Continuing installation without enterprise addons"
                        mkdir -p "$INSTALL_DIR/enterprise"
                        return 0
                        ;;
                    2)
                        # Ask for the enterprise file or directory path
                        local new_path
                        # Use -r to preserve backslashes and quotes
                        echo -n "Enter the path to the enterprise addons file or directory: "
                        read -r new_path

                        # Show exactly what was read, to verify input processing
                        echo "Input received: '$new_path'"

                        if [ -f "$new_path" ]; then
                            # User provided a direct file path
                            ODOO_ENTERPRISE_DEB="$new_path"
                            log INFO "Found enterprise addons file at: $ODOO_ENTERPRISE_DEB"
                            break
                        elif [ -d "$new_path" ]; then
                            # User provided a directory path
                            log INFO "Checking directory for .deb files: $new_path"
                            local deb_files=()
                            
                            # Find all .deb files in the directory
                            while IFS= read -r file; do
                                deb_files+=("$file")
                            done < <(find "$new_path" -maxdepth 1 -name "*.deb" -type f)
                            
                            local deb_count=${#deb_files[@]}
                            
                            if [ $deb_count -eq 0 ]; then
                                log ERROR "No .deb files found in directory: $new_path"
                                echo -e "${YELLOW}${BOLD}No .deb files found. Please choose an option:${RESET}"
                                echo -e "${CYAN}1) Continue without enterprise addons${RESET}"
                                echo -e "${CYAN}2) Specify the path to enterprise addons file or directory${RESET}"
                                echo -e "${CYAN}3) Abort installation${RESET}"
                            elif [ $deb_count -eq 1 ]; then
                                # Only one .deb file found, use it automatically
                                ODOO_ENTERPRISE_DEB="${deb_files[0]}"
                                log INFO "Found a single .deb file, using: $ODOO_ENTERPRISE_DEB"
                                break
                            else
                                # Multiple .deb files found, let user choose
                                log INFO "Found multiple .deb files, please select one:"
                                for i in "${!deb_files[@]}"; do
                                    echo -e "${CYAN}$((i+1))) ${deb_files[$i]}${RESET}"
                                done
                                echo -e "${CYAN}$((deb_count+1))) Return to previous menu${RESET}"
                                
                                local file_choice
                                while true; do
                                    read -p "Enter your choice (1-$((deb_count+1))): " file_choice
                                    if [[ "$file_choice" -ge 1 && "$file_choice" -le $deb_count ]]; then
                                        ODOO_ENTERPRISE_DEB="${deb_files[$((file_choice-1))]}"
                                        log INFO "Selected .deb file: $ODOO_ENTERPRISE_DEB"
                                        break 2  # Break out of both loops
                                    elif [ "$file_choice" -eq $((deb_count+1)) ]; then
                                        # Return to previous menu
                                        echo -e "${YELLOW}${BOLD}Enterprise addons file not found. Please choose an option:${RESET}"
                                        echo -e "${CYAN}1) Continue without enterprise addons${RESET}"
                                        echo -e "${CYAN}2) Specify the path to enterprise addons file or directory${RESET}"
                                        echo -e "${CYAN}3) Abort installation${RESET}"
                                        break  # Break out of inner loop only
                                    else
                                        log WARNING "Invalid choice, please enter a number between 1 and $((deb_count+1))"
                                    fi
                                done
                            fi
                        else
                            log ERROR "Path not found: $new_path"
                            echo -e "${YELLOW}${BOLD}Path not found. Please choose an option:${RESET}"
                            echo -e "${CYAN}1) Continue without enterprise addons${RESET}"
                            echo -e "${CYAN}2) Specify the path to enterprise addons file or directory${RESET}"
                            echo -e "${CYAN}3) Abort installation${RESET}"
                        fi
                        ;;
                    3)
                        log ERROR "Installation aborted by user"
                        exit 1
                        ;;
                    *)
                        log WARNING "Invalid choice, please enter 1, 2, or 3"
                        ;;
                esac
            done
        fi
        
        # Continue with extraction using standard Linux tools
        log INFO "Using enterprise file: $ODOO_ENTERPRISE_DEB"
        
        # Check if dpkg-deb command exists
        if ! command -v dpkg-deb &>/dev/null; then
            log ERROR "dpkg-deb command not found. Cannot extract enterprise addons."
            log ERROR "This may be due to running on a non-Debian system."
            
            echo -e "${YELLOW}${BOLD}Cannot extract enterprise addons. Please choose an option:${RESET}"
            echo -e "${CYAN}1) Continue without enterprise addons${RESET}"
            echo -e "${CYAN}2) Abort installation${RESET}"
            
            local choice
            while true; do
                read -p "Enter your choice (1-2): " choice
                case $choice in
                    1)
                        log WARNING "Continuing installation without enterprise addons"
                        mkdir -p "$INSTALL_DIR/enterprise"
                        return 0
                        ;;
                    2)
                        log ERROR "Installation aborted by user"
                        exit 1
                        ;;
                    *)
                        log WARNING "Invalid choice, please enter 1 or 2"
                        ;;
                esac
            done
        fi
        
        # Extract the DEB file
        local temp_dir=$(mktemp -d)
        if ! dpkg-deb -x "$ODOO_ENTERPRISE_DEB" "$temp_dir"; then
            log ERROR "Failed to extract enterprise addons"
            
            echo -e "${YELLOW}${BOLD}Failed to extract enterprise addons. Please choose an option:${RESET}"
            echo -e "${CYAN}1) Continue without enterprise addons${RESET}"
            echo -e "${CYAN}2) Abort installation${RESET}"
            
            local choice
            while true; do
                read -p "Enter your choice (1-2): " choice
                case $choice in
                    1)
                        log WARNING "Continuing installation without enterprise addons"
                        mkdir -p "$INSTALL_DIR/enterprise"
                        rm -rf "$temp_dir"
                        return 0
                        ;;
                    2)
                        log ERROR "Installation aborted by user"
                        rm -rf "$temp_dir"
                        exit 1
                        ;;
                    *)
                        log WARNING "Invalid choice, please enter 1 or 2"
                        ;;
                esac
            done
        fi
        
        # Check if extraction was successful
        if [ ! -d "$temp_dir/usr/lib/python3/dist-packages/odoo/addons" ]; then
            log ERROR "Enterprise addons structure not found in extracted package"
            
            echo -e "${YELLOW}${BOLD}Enterprise addons structure not found. Please choose an option:${RESET}"
            echo -e "${CYAN}1) Continue without enterprise addons${RESET}"
            echo -e "${CYAN}2) Abort installation${RESET}"
            
            local choice
            while true; do
                read -p "Enter your choice (1-2): " choice
                case $choice in
                    1)
                        log WARNING "Continuing installation without enterprise addons"
                        mkdir -p "$INSTALL_DIR/enterprise"
                        rm -rf "$temp_dir"
                        return 0
                        ;;
                    2)
                        log ERROR "Installation aborted by user"
                        rm -rf "$temp_dir"
                        exit 1
                        ;;
                    *)
                        log WARNING "Invalid choice, please enter 1 or 2"
                        ;;
                esac
            done
        fi
        
        # Create enterprise directory if it doesn't exist
        mkdir -p "$INSTALL_DIR/enterprise/"
        
        # Move enterprise addons
        mv "$temp_dir/usr/lib/python3/dist-packages/odoo/addons/"* "$INSTALL_DIR/enterprise/"
        rm -rf "$temp_dir"
        
        # Verify enterprise addons were successfully moved
        if [ -z "$(ls -A $INSTALL_DIR/enterprise/ 2>/dev/null)" ]; then
            log WARNING "Enterprise addons directory is empty. Installation will continue without enterprise features."
        else
            log INFO "Enterprise addons extracted successfully"
        fi
    fi
}

# Create backup script
create_backup_script() {
    log INFO "Creating backup script..."
    
    # Copy the existing backup script
    cp backup.sh "$INSTALL_DIR/backup.sh"
    chmod +x "$INSTALL_DIR/backup.sh"
    
    validate "backup script creation" "[ -x '$INSTALL_DIR/backup.sh' ]" "Failed to create backup script"
    log INFO "Backup script created successfully"
}

# Setup cron jobs for backup
setup_cron() {
    log INFO "Setting up cron jobs..."
    
    # Check if this is a Windows environment
    if [[ "$(uname -s)" == *"MINGW"* ]] || [[ "$(uname -s)" == *"MSYS"* ]] || [[ "$(uname -s)" == *"CYGWIN"* ]]; then
        log INFO "Windows system detected, skipping cron job setup"
        
        # Create a scheduled tasks batch file for Windows
        local batch_file="$INSTALL_DIR/setup_backup_tasks.bat"
        log INFO "Creating Windows scheduled tasks setup file: $batch_file"
        
        # Create the batch file content
        cat > "$batch_file" << EOF
@echo off
echo Setting up Windows scheduled tasks for Odoo backups
echo ---------------------------------------------------
echo.
echo This will create two scheduled tasks:
echo 1. Daily backup at 3:00 AM
echo 2. Monthly backup at 2:00 AM on the 1st of each month
echo.
echo You will need administrator privileges to create these tasks.
echo.
set /p continue=Do you want to continue? (Y/N): 

if /i "%continue%" neq "Y" goto :EOF

:: Create the tasks
schtasks /create /tn "OdooBackupDaily" /tr "$INSTALL_DIR/backup.sh backup daily" /sc daily /st 03:00 /ru SYSTEM /f
schtasks /create /tn "OdooBackupMonthly" /tr "$INSTALL_DIR/backup.sh backup monthly" /sc monthly /d 1 /st 02:00 /ru SYSTEM /f

echo.
echo Tasks created successfully. You can view them in Task Scheduler.
pause
EOF
        
        # Make the batch file executable
        chmod +x "$batch_file"
        
        log INFO "Windows scheduled tasks setup file created. Please run $batch_file as Administrator to set up automated backups."
        log WARNING "Cron jobs are not available on Windows. Manual setup of scheduled tasks is required."
        echo -e "${YELLOW}${BOLD}Note: For Windows, automated backups require manual setup.${RESET}"
        echo -e "${CYAN}Please run '${INSTALL_DIR}/setup_backup_tasks.bat' as Administrator after installation.${RESET}"
    else
        # Normal Unix/Linux cron setup
        (crontab -l 2>/dev/null || true; echo "0 3 * * * $INSTALL_DIR/backup.sh backup daily") | crontab -
        (crontab -l 2>/dev/null || true; echo "0 2 1 * * $INSTALL_DIR/backup.sh backup monthly") | crontab -
        validate "cron jobs" "crontab -l | grep -q backup.sh" "Failed to set up cron jobs"
        log INFO "Cron jobs set up successfully"
    fi
}

# Start Docker containers
start_containers() {
    log INFO "Starting Docker containers..."
    cd "$INSTALL_DIR"
    
    # Check for docker-compose.yml file
    if [ ! -f "$INSTALL_DIR/docker-compose.yml" ]; then
        log ERROR "docker-compose.yml file not found in $INSTALL_DIR"
        exit 1
    fi
    
    # Check for existing containers with the same names and remove them
    log INFO "Checking for existing containers..."
    if docker ps -a | grep -q "$DB_CONTAINER"; then
        log INFO "Existing container $DB_CONTAINER found, removing it..."
        docker stop "$DB_CONTAINER" >/dev/null 2>&1 || true
        docker rm "$DB_CONTAINER" >/dev/null 2>&1 || true
    fi
    if docker ps -a | grep -q "$ODOO_CONTAINER_NAME"; then
        log INFO "Existing container $ODOO_CONTAINER_NAME found, removing it..."
        docker stop "$ODOO_CONTAINER_NAME" >/dev/null 2>&1 || true
        docker rm "$ODOO_CONTAINER_NAME" >/dev/null 2>&1 || true
    fi
    
    # Clean up any existing networks (from previous installations)
    log INFO "Cleaning up any existing Docker networks..."
    docker network ls --filter "name=odoo" -q | xargs -r docker network rm >/dev/null 2>&1 || true
    
    # Pull images
    log INFO "Pulling Docker images..."
    docker compose pull
    
    # Start database container first
    log INFO "Starting PostgreSQL container..."
    docker compose up -d db
    
    # Wait for PostgreSQL to be ready
    log INFO "Waiting for PostgreSQL to be ready..."
    local pg_ready=false
    local max_attempts=10
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if docker exec $DB_CONTAINER pg_isready -U $DB_USER > /dev/null 2>&1; then
            pg_ready=true
            log INFO "PostgreSQL is ready"
            break
        fi
        log INFO "Waiting for PostgreSQL (attempt $attempt/$max_attempts)..."
        sleep 3
        attempt=$((attempt + 1))
    done
    
    if [ "$pg_ready" != "true" ]; then
        log ERROR "PostgreSQL failed to become ready"
        exit 1
    fi
    
    # Start Odoo container
    log INFO "Starting Odoo container..."
    docker compose up -d web
    
    # Wait for services to be ready
    log INFO "Waiting for services to start..."
    sleep 10
    
    # Validate containers
    validate "Odoo container" "docker ps | grep -q '$ODOO_CONTAINER_NAME'" "Odoo container failed to start"
    validate "PostgreSQL container" "docker ps | grep -q '$DB_CONTAINER'" "PostgreSQL container failed to start"
}

# Initialize database
initialize_database() {
    log INFO "Initializing Odoo database..."
    
    # Stop and remove Odoo container
    log INFO "Stopping and removing Odoo container to initialize database..."
    docker stop $ODOO_CONTAINER_NAME >/dev/null 2>&1 || true
    docker rm $ODOO_CONTAINER_NAME >/dev/null 2>&1 || true
    
    # Ensure proper permissions on the filestore directory
    log INFO "Setting correct permissions for filestore directory..."
    mkdir -p "$INSTALL_DIR/volumes/odoo-data/filestore/$DB_NAME"
    
    if [ "$IS_WINDOWS" = "true" ]; then
        log INFO "On Windows: Volume permissions are managed by the host filesystem"
        log INFO "Creating directory structure without changing permissions..."
        
        # On Windows, just ensure the directories exist without trying to change permissions
        docker run --rm \
            -v "$INSTALL_DIR/volumes/odoo-data:/var/lib/odoo" \
            odoo:17.0 \
            sh -c "mkdir -p /var/lib/odoo/filestore/$DB_NAME" || true
            
        # Provide guidance for the user
        log INFO "For Windows users:"
        log INFO "1. Make sure your Windows user has full control permissions on $INSTALL_DIR/volumes"
        log INFO "2. Docker volume mounts on Windows have different permission behavior than Linux"
        log INFO "3. If database operations fail, try running fix-permissions.sh or restart Docker Desktop"
    else
        chmod -R 777 "$INSTALL_DIR/volumes/odoo-data" 2>/dev/null || log WARNING "Could not set permissions for data directory"
        chown -R 101:101 "$INSTALL_DIR/volumes/odoo-data" 2>/dev/null || log WARNING "Could not set ownership for data directory"
    fi
    
    # Initialize database with base module
    log INFO "Initializing database with base module..."
    docker run --rm --name $ODOO_CONTAINER_NAME \
        --network $(docker inspect $DB_CONTAINER --format '{{.HostConfig.NetworkMode}}') \
        -v "$INSTALL_DIR/config:/etc/odoo" \
        -v "$INSTALL_DIR/volumes/odoo-data:/var/lib/odoo" \
        -v "$INSTALL_DIR/enterprise:/mnt/enterprise" \
        -v "$INSTALL_DIR/addons:/mnt/extra-addons" \
        -v "$INSTALL_DIR/logs:/var/log/odoo" \
        -e HOST=db \
        -e PORT=$DB_PORT \
        -e USER=$DB_USER \
        -e PASSWORD=$DB_PASS \
        -e PGDATABASE=$DB_NAME \
        odoo:17.0 \
        -- --database $DB_NAME --init base --without-demo=all --stop-after-init --log-level=error > /dev/null 2>&1
    
    # Check if initialization was successful
    local init_status=$?
    
    if [ $init_status -ne 0 ]; then
        log ERROR "Failed to initialize database with base module"
        return 1
    fi
    
    log INFO "Database initialized successfully with base module"
    
    # Restart the normal container
    cd "$INSTALL_DIR"
    docker compose up -d web
    
    # Wait for Odoo to start
    log INFO "Waiting for Odoo to start..."
    sleep 15
    
    return 0
}

# Check service health
check_service_health() {
    local max_attempts=10
    local attempt=1

    log INFO "Checking service health..."

    while [ $attempt -le $max_attempts ]; do
        # Check if database is accessible
        if docker exec $DB_CONTAINER psql -U $DB_USER -c "SELECT 1" >/dev/null 2>&1; then
            log INFO "Database is accessible"
            
            # Test database existence
            if docker exec $DB_CONTAINER psql -U $DB_USER -lqt | cut -d \| -f 1 | grep -qw $DB_NAME; then
                log INFO "Database $DB_NAME exists"
                
                # Check if Odoo web interface is responding
                if curl -s --max-time 5 http://localhost:$ODOO_PORT/web/database/selector > /dev/null; then
                    log INFO "Odoo is fully operational"
                    return 0
                else
                    log INFO "Odoo web interface is not responding yet"
                fi
            else
                log INFO "Database $DB_NAME does not exist yet"
            fi
        else
            log INFO "Database is not accessible yet"
        fi
        
        log INFO "Waiting for services (attempt $attempt/$max_attempts)..."
        sleep 3
        attempt=$((attempt + 1))
    done
    
    log ERROR "Services failed to become ready after multiple attempts"
    return 1
}

# Verify installation
verify_installation() {
    log INFO "Verifying installation..."
    
    # Check database existence
    local db_exists=$(docker exec $DB_CONTAINER psql -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" -U $DB_USER)
    
    if [ "$db_exists" != "1" ]; then
        log ERROR "Database verification failed: Database $DB_NAME does not exist"
        return 1
    fi
    
    # Check if ir_module_module table exists (indicates base module installed)
    local table_exists=$(docker exec $DB_CONTAINER psql -tAc "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'ir_module_module')" -U $DB_USER -d $DB_NAME)
    
    if [ "$table_exists" != "t" ]; then
        log ERROR "Database verification failed: ir_module_module table does not exist"
        return 1
    fi
    
    # Check if Odoo web interface is accessible
    local response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$ODOO_PORT/web/login)
    
    if [ "$response" != "200" ]; then
        log ERROR "Web interface verification failed: Got response code $response"
        return 1
    fi

    log INFO "Installation verified successfully"
    return 0
}

# Set report URL
set_report_url() {
    log INFO "Setting report.url parameter..."
    
    # Create a temporary Python script file
    local temp_script=$(mktemp)
    
    # Write the Python commands to the temporary file
    cat > "$temp_script" << EOF
from odoo import api, SUPERUSER_ID
env = api.Environment(odoo.registry('$DB_NAME').cursor(), SUPERUSER_ID, {})
param = env['ir.config_parameter'].sudo()
param.set_param('report.url', 'http://$PUBLIC_IP:$ODOO_PORT')
env.cr.commit()
EOF
    
    # Make the script readable by everyone
    chmod 644 "$temp_script"
    
    # Execute the script using odoo shell with a different HTTP port
    docker exec -i $ODOO_CONTAINER_NAME odoo shell --http-port=8070 -d $DB_NAME < "$temp_script" 2>/dev/null
    
    # Check the status
    local status=$?
    
    # Clean up the temporary file
    rm -f "$temp_script"
    
    if [ $status -eq 0 ]; then
        log INFO "report.url parameter set successfully to http://$PUBLIC_IP:$ODOO_PORT"
        return 0
    else
        log ERROR "Failed to set report.url parameter"
        return 1
    fi
}

# Create configuration file
create_config_file() {
    log INFO "Creating Odoo configuration file..."
    
    # Create config directory if it doesn't exist
    mkdir -p "$INSTALL_DIR/config"
    
    # Copy the pre-configured odoo.conf file
    log INFO "Copying pre-configured odoo.conf file..."
    cp "$SETUP_DIR/config/odoo.conf" "$INSTALL_DIR/config/odoo.conf"
    
    # Add Docker logging configuration if not already present
    if ! grep -q "log_level" "$INSTALL_DIR/config/odoo.conf"; then
        log INFO "Adding Docker logging configuration..."
        echo "log_level = info" >> "$INSTALL_DIR/config/odoo.conf"
        echo "log_handler = [\":INFO\"]" >> "$INSTALL_DIR/config/odoo.conf"
    fi
    
    # Set more permissive permissions to allow container to read it
    log INFO "Setting permissions on configuration file..."
    set_permissions "$INSTALL_DIR/config/odoo.conf"
    
    log INFO "Configuration file created successfully"
}

# Verify directory permissions
verify_permissions() {
    log INFO "Verifying directory permissions..."
    
    # Check if sessions directory exists and has correct permissions
    if [ ! -d "$INSTALL_DIR/volumes/odoo-data/sessions" ]; then
        log INFO "Sessions directory does not exist, creating it..."
        mkdir -p "$INSTALL_DIR/volumes/odoo-data/sessions"
    fi
    
    # Create database-specific filestore directory
    if [ ! -d "$INSTALL_DIR/volumes/odoo-data/filestore/$DB_NAME" ]; then
        log INFO "Database filestore directory does not exist, creating it..."
        mkdir -p "$INSTALL_DIR/volumes/odoo-data/filestore/$DB_NAME"
    fi
    
    # Set correct permissions
    log INFO "Setting correct permissions for Odoo directories..."
    set_permissions "$INSTALL_DIR/volumes/odoo-data/sessions"
    set_permissions "$INSTALL_DIR/volumes/odoo-data/filestore"
    set_permissions "$INSTALL_DIR/volumes/odoo-data/filestore/$DB_NAME"
    
    # Set permissions for the entire data directory for good measure
    if [ "$IS_WINDOWS" = "true" ]; then
        log INFO "On Windows: Skipping chmod/chown for data directory (not fully supported in Git Bash)"
    else
        chmod -R 777 "$INSTALL_DIR/volumes/odoo-data" 2>/dev/null || log WARNING "Could not set permissions for data directory"
        chown -R 101:101 "$INSTALL_DIR/volumes/odoo-data" 2>/dev/null || log WARNING "Could not set ownership for data directory"
    fi
    
    # Verify other critical directories
    for dir in "$INSTALL_DIR/volumes/odoo-data/filestore" "$INSTALL_DIR/logs" "$INSTALL_DIR/config"; do
        if [ -d "$dir" ]; then
            log INFO "Setting permissions for $dir..."
            set_permissions "$dir"
        fi
    done
    
    # Make sure config file is readable
    if [ -f "$INSTALL_DIR/config/odoo.conf" ]; then
        log INFO "Setting permissions for odoo.conf..."
        set_permissions "$INSTALL_DIR/config/odoo.conf"
    fi
    
    log INFO "Directory permissions verified"
}

# Copy necessary files
copy_necessary_files() {
    log INFO "Copying necessary files from setup directory..."
    
    # Get absolute path to setup directory
    cd "$SETUP_DIR"
    SETUP_PATH=$(pwd)
    log INFO "Setup directory: $SETUP_PATH"
    
    # Copy docker-compose.yml to INSTALL_DIR
    log INFO "Copying docker-compose.yml to $INSTALL_DIR..."
    cp "$SETUP_PATH/docker-compose.yml" "$INSTALL_DIR/"
    validate "docker-compose.yml file" "[ -f '$INSTALL_DIR/docker-compose.yml' ]" "Failed to copy docker-compose.yml"
    
    # Copy backup.sh and other necessary scripts
    log INFO "Copying backup script to $INSTALL_DIR..."
    cp "$SETUP_PATH/backup.sh" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/backup.sh"
    validate "backup script" "[ -x '$INSTALL_DIR/backup.sh' ]" "Failed to copy backup.sh"
    
    # Copy staging.sh
    log INFO "Copying staging script to $INSTALL_DIR..."
    cp "$SETUP_PATH/staging.sh" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/staging.sh"
    validate "staging script" "[ -x '$INSTALL_DIR/staging.sh' ]" "Failed to copy staging.sh"
    
    # Copy git_panel.sh
    log INFO "Copying git panel script to $INSTALL_DIR..."
    cp "$SETUP_PATH/git_panel.sh" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/git_panel.sh"
    validate "git panel script" "[ -x '$INSTALL_DIR/git_panel.sh' ]" "Failed to copy git_panel.sh"
    
    # Copy fix-permissions.sh
    log INFO "Copying permissions fix script to $INSTALL_DIR..."
    cp "$SETUP_PATH/fix-permissions.sh" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/fix-permissions.sh"
    validate "permissions fix script" "[ -x '$INSTALL_DIR/fix-permissions.sh' ]" "Failed to copy fix-permissions.sh"
    
    log INFO "Necessary files copied successfully"
}

# Fix filestore permissions for database operations
fix_filestore_permissions() {
    log INFO "Fixing filestore permissions for database operations..."
    
    if [ "$IS_WINDOWS" = "true" ]; then
        log INFO "On Windows: Volume permissions must be managed by the host filesystem"
        
        # Try to use a running container first
        if docker ps | grep -q "$ODOO_CONTAINER_NAME"; then
            log INFO "Using running container to create necessary directories..."
            
            # Just create the directories without trying to change permissions
            docker exec $ODOO_CONTAINER_NAME sh -c "mkdir -p /var/lib/odoo/filestore" || true
        else
            # No running container, use temporary container
            log INFO "No running container found, using temporary container..."
            
            docker run --rm \
                -v "$INSTALL_DIR/volumes/odoo-data:/var/lib/odoo" \
                odoo:17.0 \
                sh -c "mkdir -p /var/lib/odoo/filestore" || true
        fi
        
        # On Windows, we need to configure permissions from Windows itself
        log INFO "For Windows Docker volumes, follow these steps to fix permissions:"
        log INFO "1. Open Explorer and navigate to: $INSTALL_DIR/volumes/odoo-data"
        log INFO "2. Right-click on 'filestore' folder → Properties → Security tab"
        log INFO "3. Click 'Edit' and then 'Add'"
        log INFO "4. Enter 'Everyone' and click 'Check Names' → OK"
        log INFO "5. Select 'Everyone' and check 'Full control' → Apply → OK"
        log INFO "6. Restart Docker Desktop and the Odoo container"
        
        # Alternative solution using docker-compose down/up
        log INFO ""
        log INFO "Alternatively, try the following command sequence to recreate containers:"
        log INFO "cd $INSTALL_DIR && docker-compose down && docker-compose up -d"
    else
        # Directly fix permissions on the host
        chmod -R 777 "$INSTALL_DIR/volumes/odoo-data/filestore" 2>/dev/null || log WARNING "Could not set permissions for filestore directory"
        chown -R 101:101 "$INSTALL_DIR/volumes/odoo-data/filestore" 2>/dev/null || log WARNING "Could not set ownership for filestore directory"
    fi
    
    log INFO "Filestore permissions process completed"
}

# Main installation process
main() {
    show_banner
    log INFO "Starting Odoo 17 installation for {client_name}"
    
    check_prerequisites
    create_directories
    create_config_file
    extract_enterprise
    create_backup_script
    setup_cron
    verify_permissions
    copy_necessary_files
    
    # Stop any running containers to apply configuration changes
    log INFO "Stopping any running containers to apply configuration changes..."
    cd "$INSTALL_DIR"
    docker compose down -v 2>/dev/null || true
    
    start_containers
    initialize_database
    check_service_health
    verify_installation
    set_report_url
    
    # Fix filestore permissions after installation
    fix_filestore_permissions
    
    if [ $? -eq 0 ]; then
        display_cleanup_message
    else
        log ERROR "Installation completed but verification failed"
        exit 1
    fi
}

# Run main function
main 