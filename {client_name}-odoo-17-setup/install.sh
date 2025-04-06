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

# Progress display variables
STEP=0
TOTAL_STEPS=10  # Update this as needed

# Constants
INSTALL_DIR="{path_to_install}/{client_name}-odoo-17"
VERBOSE=false  # Set to true for more detailed output
TEMP_LOG="/tmp/odoo_install.log"
LOG_FILE="$INSTALL_DIR/logs/install.log"
ODOO_ENTERPRISE_DEB="./odoo_17.0+e.latest_all.deb"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Database and authentication constants
DB_NAME="postgres_{client_name}"
DB_USER="odoo"
DB_PASS="{client_password}"
ADMIN_PASS="{client_password}"
CONTAINER_NAME="odoo17-{client_name}"
DB_CONTAINER="db-{client_name}"

# Store system information
SYS_MEMORY=""
SYS_CPU=""
SYS_DISK=""
SYS_OS=""
DOCKER_VERSION=""
DOCKER_COMPOSE_VERSION=""
EXISTING_CONTAINERS=""
PORTS_IN_USE=""

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

    echo -e "${level_color}[$TIMESTAMP] [$level]${RESET} $*" | tee -a "$TEMP_LOG"
}

# Display progress
show_progress() {
    STEP=$((STEP + 1))
    echo -e "\n${BLUE}${BOLD}[$STEP/$TOTAL_STEPS]${RESET} ${CYAN}${BOLD}$1${RESET}\n"
}

# Show spinner for long-running operations
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep -w $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# Function to request user confirmation
confirm() {
    local prompt=$1
    local default=${2:-Y}

    if [ "$default" = "Y" ]; then
        local options="[Y/n]"
    else
        local options="[y/N]"
    fi

    echo -e "${YELLOW}${BOLD}$prompt $options${RESET}"
    read -r response

    if [ -z "$response" ]; then
        response=$default
    fi

    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Display banner
show_banner() {
    echo -e "${BG_BLUE}${WHITE}${BOLD}"
    echo "  ___       _                   _  ______ "
    echo " / _ \   __| |  ___    ___     / ||_____/ "
    echo "| | | | / _\` | / _ \  / _ \   / /    / /  "
    echo "| |_| || (_| || (_) || (_) | / /    / /   "
    echo " \___/  \__,_| \___/  \___/ /_/    /_/    "
    echo "                                          "
    echo -e "${RESET}"
    echo -e "${CYAN}${BOLD}Installation Script for {client_name}${RESET}"
    echo -e "${DIM}Created: $(date)${RESET}"
    echo
}

# Error handling
set -e
trap 'cleanup_on_error' ERR

# Cleanup function for error handling
cleanup_on_error() {
    log ERROR "Installation failed, cleaning up..."
    echo -e "${BG_RED}${WHITE}${BOLD} INSTALLATION FAILED ${RESET}"
    echo -e "${RED}Check the log file at $LOG_FILE for details${RESET}"

    if confirm "Would you like to clean up the partial installation?" "Y"; then
        cd "$INSTALL_DIR" 2>/dev/null || true
        docker-compose down -v 2>/dev/null || true
        rm -rf volumes/* 2>/dev/null || true
        echo -e "${YELLOW}Cleanup completed. Partial installation removed.${RESET}"
    else
        echo -e "${YELLOW}Leaving partial installation in place.${RESET}"
    fi

    exit 1
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

validate_installation_path() {
    if [ ! -d "$(dirname "$INSTALL_DIR")" ]; then
        log ERROR "Installation path parent directory does not exist: $(dirname "$INSTALL_DIR")"
        echo -e "${RED}${BOLD}⚠ Installation path parent directory does not exist: $(dirname "$INSTALL_DIR")${RESET}"
        echo -e "${YELLOW}This could be because the path specified in the configuration file is incorrect.${RESET}"
        echo -e "${YELLOW}Solution: Update 'path_to_install' in your configuration file to an existing directory.${RESET}"
        exit 1
    fi
    
    if [ ! -w "$(dirname "$INSTALL_DIR")" ]; then
        log ERROR "No write permission to $(dirname "$INSTALL_DIR")"
        echo -e "${RED}${BOLD}⚠ Cannot create directories in $(dirname "$INSTALL_DIR")${RESET}"
        echo -e "${YELLOW}This could be because the path requires sudo permission.${RESET}"
        echo -e "${YELLOW}Solution: Update 'path_to_install' in your configuration file or run with sudo.${RESET}"
        exit 1
    fi
}

validate_docker_volumes() {
    local test_dir="$INSTALL_DIR/volumes/test_docker_volume"
    mkdir -p "$test_dir"
    
    if [ ! -d "$test_dir" ]; then
        log ERROR "Failed to create test directory for Docker volumes: $test_dir"
        echo -e "${RED}${BOLD}⚠ Failed to create test directory for Docker volumes${RESET}"
        echo -e "${YELLOW}This could be because of filesystem permissions or mount issues.${RESET}"
        echo -e "${YELLOW}Solution: Check that the path is on a supported filesystem and has proper permissions.${RESET}"
        exit 1
    fi
    
    rmdir "$test_dir"
}

check_docker() {
    log INFO "Checking Docker availability..."
    
    if ! command -v docker &>/dev/null; then
        log ERROR "Docker is not installed"
        echo -e "${RED}${BOLD}⚠ Docker is not installed${RESET}"
        echo -e "${YELLOW}This installation requires Docker to run Odoo.${RESET}"
        echo -e "${YELLOW}Solution: Install Docker using the official instructions:${RESET}"
        echo -e "${YELLOW}https://docs.docker.com/engine/install/${RESET}"
        exit 1
    fi
    
    if ! command -v docker-compose &>/dev/null; then
        log ERROR "Docker Compose is not installed"
        echo -e "${RED}${BOLD}⚠ Docker Compose is not installed${RESET}"
        echo -e "${YELLOW}This installation requires Docker Compose to orchestrate containers.${RESET}"
        echo -e "${YELLOW}Solution: Install Docker Compose using the official instructions:${RESET}"
        echo -e "${YELLOW}https://docs.docker.com/compose/install/${RESET}"
        exit 1
    fi
    
    if ! docker info &>/dev/null; then
        log ERROR "Docker daemon is not running"
        echo -e "${RED}${BOLD}⚠ Docker daemon is not running${RESET}"
        echo -e "${YELLOW}Solution: Start Docker service with:${RESET}"
        echo -e "${YELLOW}sudo systemctl start docker${RESET}"
        exit 1
    fi
    
    if ! docker ps &>/dev/null; then
        log WARNING "Current user may not have permission to run Docker"
        echo -e "${YELLOW}${BOLD}⚠ Current user may not have permission to run Docker${RESET}"
        echo -e "${YELLOW}Solution: Add your user to the docker group:${RESET}"
        echo -e "${YELLOW}sudo usermod -aG docker $USER${RESET}"
        echo -e "${YELLOW}Then log out and log back in, or run this script with sudo${RESET}"
    fi
    
    log INFO "Docker is available and running"
}

# Analyze system
analyze_system() {
    show_progress "Analyzing System"
    
    check_docker

    log INFO "Gathering system information..."

    # OS Information
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        SYS_OS="$NAME $VERSION"
        log INFO "Detected OS: $SYS_OS"
    else
        SYS_OS="Unknown"
        log WARNING "Could not detect OS"
    fi

    # Memory
    if command -v free >/dev/null 2>&1; then
        SYS_MEMORY=$(free -h | awk '/^Mem:/ {print $2}')
        log INFO "Total Memory: $SYS_MEMORY"
    else
        SYS_MEMORY="Unknown"
        log WARNING "Could not detect system memory"
    fi

    # CPU
    if [ -f /proc/cpuinfo ]; then
        SYS_CPU=$(grep -c "^processor" /proc/cpuinfo)
        log INFO "CPU Cores: $SYS_CPU"
    else
        SYS_CPU="Unknown"
        log WARNING "Could not detect CPU information"
    fi

    # Disk Space
    if command -v df >/dev/null 2>&1; then
        SYS_DISK=$(df -h / | awk 'NR==2 {print $4}')
        log INFO "Available Disk Space: $SYS_DISK"
    else
        SYS_DISK="Unknown"
        log WARNING "Could not detect disk space"
    fi

    # Docker Version
    if command -v docker >/dev/null 2>&1; then
        DOCKER_VERSION=$(docker --version | cut -d' ' -f3 | tr -d ',')
        log INFO "Docker Version: $DOCKER_VERSION"
    else
        DOCKER_VERSION="Not Installed"
        log ERROR "Docker is not installed"
        echo -e "${BG_RED}${WHITE}${BOLD} DOCKER NOT FOUND ${RESET}"
        echo -e "${RED}Docker is required for this installation. Please install Docker first.${RESET}"
        echo "Visit https://docs.docker.com/engine/install/ for installation instructions."
        exit 1
    fi

    # Docker Compose Version
    if command -v docker-compose >/dev/null 2>&1; then
        DOCKER_COMPOSE_VERSION=$(docker-compose --version | cut -d' ' -f3 | tr -d ',')
        log INFO "Docker Compose Version: $DOCKER_COMPOSE_VERSION (standalone)"
    elif docker compose version >/dev/null 2>&1; then
        DOCKER_COMPOSE_VERSION=$(docker compose version --short)
        log INFO "Docker Compose Version: $DOCKER_COMPOSE_VERSION (plugin)"
    else
        DOCKER_COMPOSE_VERSION="Not Installed"
        log ERROR "Docker Compose is not installed"
        echo -e "${BG_RED}${WHITE}${BOLD} DOCKER COMPOSE NOT FOUND ${RESET}"
        echo -e "${RED}Docker Compose is required for this installation. Please install Docker Compose first.${RESET}"
        echo "Visit https://docs.docker.com/compose/install/ for installation instructions."
        exit 1
    fi

    # Check existing containers
    EXISTING_CONTAINERS=$(docker ps -a --format "{{.Names}}" | grep -E "odoo|postgres" 2>/dev/null || echo "None")
    if [ "$EXISTING_CONTAINERS" != "None" ]; then
        log WARNING "Found existing Odoo/Postgres containers: $EXISTING_CONTAINERS"
        echo -e "${YELLOW}${BOLD}Warning: Existing Docker containers detected:${RESET}"
        docker ps -a | grep -E "odoo|postgres" || true
        echo
        if ! confirm "Do you want to continue with the installation? This may conflict with existing containers."; then
            echo -e "${RED}Installation cancelled by user.${RESET}"
            exit 0
        fi
    else
        log INFO "No existing Odoo/Postgres containers found"
    fi

    # Check ports in use
    PORTS_IN_USE=""
    if command -v netstat >/dev/null 2>&1; then
        if netstat -tuln | grep -q ":8069"; then
            PORTS_IN_USE="8069"
            log WARNING "Port 8069 is already in use"
        fi
        if netstat -tuln | grep -q ":5432"; then
            if [ -n "$PORTS_IN_USE" ]; then
                PORTS_IN_USE="$PORTS_IN_USE, 5432"
            else
                PORTS_IN_USE="5432"
            fi
            log WARNING "Port 5432 is already in use"
        fi
    elif command -v ss >/dev/null 2>&1; then
        if ss -tuln | grep -q ":8069"; then
            PORTS_IN_USE="8069"
            log WARNING "Port 8069 is already in use"
        fi
        if ss -tuln | grep -q ":5432"; then
            if [ -n "$PORTS_IN_USE" ]; then
                PORTS_IN_USE="$PORTS_IN_USE, 5432"
            else
                PORTS_IN_USE="5432"
            fi
            log WARNING "Port 5432 is already in use"
        fi
    fi

    if [ -n "$PORTS_IN_USE" ]; then
        echo -e "${YELLOW}${BOLD}Warning: The following ports are already in use: $PORTS_IN_USE${RESET}"
        echo -e "${YELLOW}This may prevent Odoo from starting properly.${RESET}"
        if ! confirm "Do you want to continue with the installation?"; then
            echo -e "${RED}Installation cancelled by user.${RESET}"
            exit 0
        fi
    else
        log INFO "Required ports (8069, 5432) are available"
    fi
}

# Show pre-installation summary
show_summary() {
    echo -e "\n${BG_BLUE}${WHITE}${BOLD} PRE-INSTALLATION SUMMARY ${RESET}\n"
    echo -e "${CYAN}${BOLD}System Information:${RESET}"
    echo -e "  ${BOLD}Operating System:${RESET} $SYS_OS"
    echo -e "  ${BOLD}Memory:${RESET}          $SYS_MEMORY"
    echo -e "  ${BOLD}CPU Cores:${RESET}       $SYS_CPU"
    echo -e "  ${BOLD}Disk Space:${RESET}      $SYS_DISK"
    echo -e "  ${BOLD}Docker:${RESET}          $DOCKER_VERSION"
    echo -e "  ${BOLD}Docker Compose:${RESET}  $DOCKER_COMPOSE_VERSION"

    echo -e "\n${CYAN}${BOLD}Installation Details:${RESET}"
    echo -e "  ${BOLD}Client Name:${RESET}     {client_name}"
    echo -e "  ${BOLD}Install Directory:${RESET} $INSTALL_DIR"
    echo -e "  ${BOLD}Database:${RESET}        $DB_NAME"
    echo -e "  ${BOLD}Database User:${RESET}   $DB_USER"

    echo -e "\n${CYAN}${BOLD}Actions to be performed:${RESET}"
    echo -e "  ${GREEN}✓${RESET} Create directory structure"
    echo -e "  ${GREEN}✓${RESET} Extract enterprise addons"
    echo -e "  ${GREEN}✓${RESET} Configure database and Odoo settings"
    echo -e "  ${GREEN}✓${RESET} Set up backup and maintenance scripts"
    echo -e "  ${GREEN}✓${RESET} Configure SSL/HTTPS (if requested)"
    echo -e "  ${GREEN}✓${RESET} Start Docker containers"
    echo -e "  ${GREEN}✓${RESET} Initialize the database"

    if [ -n "$PORTS_IN_USE" ]; then
        echo -e "\n${YELLOW}${BOLD}⚠ Warning: Ports in use:${RESET} $PORTS_IN_USE"
    fi

    if [ "$EXISTING_CONTAINERS" != "None" ]; then
        echo -e "\n${YELLOW}${BOLD}⚠ Warning: Existing containers:${RESET} $EXISTING_CONTAINERS"
    fi

    echo -e "\nInstallation log will be saved to: ${UNDERLINE}$LOG_FILE${RESET}\n"

    if ! confirm "Do you want to proceed with the installation?"; then
        echo -e "${RED}Installation cancelled by user.${RESET}"
        exit 0
    fi
}

# Create directory structure
create_directories() {
    show_progress "Creating Directory Structure"

    log INFO "Creating directory structure..."

    validate_installation_path
    
    validate_docker_volumes

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
    chown -R 101:101 "$INSTALL_DIR/volumes/odoo-data" "$INSTALL_DIR/volumes/postgres-data" "$INSTALL_DIR/logs" 2>/dev/null || true
    chmod -R 777 "$INSTALL_DIR/volumes/odoo-data" "$INSTALL_DIR/volumes/postgres-data" "$INSTALL_DIR/logs"

    # Move temporary log to final location
    mkdir -p "$(dirname "$LOG_FILE")"
    mv "$TEMP_LOG" "$LOG_FILE" 2>/dev/null || true
    log INFO "Directory structure created successfully"
    echo -e "${GREEN}${BOLD}✓${RESET} Directory structure created"
}

# Check prerequisites
check_prerequisites() {
    show_progress "Checking Prerequisites"

    log INFO "Checking prerequisites..."

    # Check Docker
    validate "Docker installation" "command -v docker" "Docker is not installed"
    log INFO "Docker is installed: $(docker --version)"

    # Check Docker Compose
    if command -v docker-compose &>/dev/null; then
        log INFO "Docker Compose is installed (standalone): $(docker-compose --version)"
    elif docker compose version &>/dev/null; then
        log INFO "Docker Compose is installed (plugin): $(docker compose version)"
    else
        log ERROR "Docker Compose is not installed"
        exit 1
    fi

    # Check user permissions
    if ! groups | grep -q docker; then
        log WARNING "Current user is not in docker group. You might need sudo for docker commands."
        echo -e "${YELLOW}${BOLD}Warning:${RESET} Current user is not in the docker group."
        echo -e "${YELLOW}You may need to use 'sudo' for docker commands, or add your user to the docker group.${RESET}"

        if confirm "Do you want to add the current user to the docker group?"; then
            sudo usermod -aG docker $USER
            echo -e "${GREEN}User added to docker group. You may need to log out and log back in for this to take effect.${RESET}"
        fi
    else
        log INFO "Current user is in docker group"
        echo -e "${GREEN}${BOLD}✓${RESET} User has proper Docker permissions"
    fi

    # Check port availability
    if [ -z "$PORTS_IN_USE" ]; then
        log INFO "Required ports are available"
        echo -e "${GREEN}${BOLD}✓${RESET} Required ports are available"
    fi
}

# Extract enterprise addons
extract_enterprise() {
    show_progress "Extracting Enterprise Addons"

    log INFO "Extracting enterprise addons..."

    if [ ! -f "$ODOO_ENTERPRISE_DEB" ]; then
        log WARNING "Enterprise DEB file not found: $ODOO_ENTERPRISE_DEB"
        echo -e "${YELLOW}${BOLD}⚠ Enterprise DEB file not found${RESET}"
        echo -e "${YELLOW}Please place the Odoo Enterprise .deb file at:${RESET}"
        echo -e "${UNDERLINE}$ODOO_ENTERPRISE_DEB${RESET}"

        if confirm "Do you want to continue without enterprise addons?"; then
            log INFO "Continuing without enterprise addons"
            echo -e "${YELLOW}Continuing without enterprise addons. Community version will be used.${RESET}"
            return 0
        else
            log ERROR "Installation cancelled: Enterprise DEB file is required"
            echo -e "${RED}Installation cancelled by user.${RESET}"
            exit 1
        fi
    fi

    log INFO "Extracting enterprise addons from DEB file..."
    echo -e "${CYAN}Extracting enterprise addons...${RESET}"

    local temp_dir=$(mktemp -d)
    if ! dpkg-deb -x "$ODOO_ENTERPRISE_DEB" "$temp_dir" 2>/dev/null; then
        log ERROR "Failed to extract enterprise addons: Not a valid Debian package"
        echo -e "${RED}${BOLD}⚠ Failed to extract enterprise addons: Not a valid Debian package${RESET}"
        rm -rf "$temp_dir"

        if confirm "Do you want to continue without enterprise addons?"; then
            log INFO "Continuing without enterprise addons"
            echo -e "${YELLOW}Continuing without enterprise addons. Community version will be used.${RESET}"
            return 0
        else
            log ERROR "Installation cancelled: Failed to extract enterprise addons"
            echo -e "${RED}Installation cancelled by user.${RESET}"
            exit 1
        fi
    fi

    # Validate extraction
    if [ ! -d "$temp_dir/usr/lib/python3/dist-packages/odoo/addons" ]; then
        log ERROR "Failed to extract enterprise addons: Invalid package structure"
        echo -e "${RED}${BOLD}⚠ Failed to extract enterprise addons: Invalid package structure${RESET}"
        rm -rf "$temp_dir"

        if confirm "Do you want to continue without enterprise addons?"; then
            log INFO "Continuing without enterprise addons"
            echo -e "${YELLOW}Continuing without enterprise addons. Community version will be used.${RESET}"
            return 0
        else
            log ERROR "Installation cancelled: Failed to extract enterprise addons"
            echo -e "${RED}Installation cancelled by user.${RESET}"
            exit 1
        fi
    fi

    # Move enterprise addons
    mv "$temp_dir/usr/lib/python3/dist-packages/odoo/addons/"* "$INSTALL_DIR/enterprise/"
    rm -rf "$temp_dir"

    # Validate move
    validate "Enterprise addons availability" "[ -n '$(ls -A $INSTALL_DIR/enterprise/)' ]" "Enterprise addons directory is empty"
    
    log INFO "Installing required Python packages..."
    echo -e "${CYAN}Installing required Python packages...${RESET}"
    if [ -f "$INSTALL_DIR/requirements.txt" ]; then
        pip3 install -r "$INSTALL_DIR/requirements.txt"
        validate "Python packages installation" "pip3 list | grep -q pycryptodome" "Failed to install required Python packages"
        log INFO "Required Python packages installed successfully"
        echo -e "${GREEN}${BOLD}✓${RESET} Required Python packages installed successfully"
    fi
    
    log INFO "Enterprise addons extracted successfully"
    echo -e "${GREEN}${BOLD}✓${RESET} Enterprise addons extracted successfully"
}

# Create backup script
create_backup_script() {
    show_progress "Setting Up Backup and Maintenance Scripts"

    log INFO "Creating scripts..."

    # Copy the existing backup script
    cp backup.sh "$INSTALL_DIR/backup.sh"
    chmod +x "$INSTALL_DIR/backup.sh"

    # Copy staging script
    cp staging.sh "$INSTALL_DIR/staging.sh"
    chmod +x "$INSTALL_DIR/staging.sh"

    cp git_panel.sh "$INSTALL_DIR/git_panel.sh"
    chmod +x "$INSTALL_DIR/git_panel.sh"

    # Copy SSL setup script if it exists
    if [ -f "ssl-setup.sh" ]; then
        cp ssl-setup.sh "$INSTALL_DIR/ssl-setup.sh"
        chmod +x "$INSTALL_DIR/ssl-setup.sh"
    fi

    validate "scripts creation" "[ -x '$INSTALL_DIR/backup.sh' ]" "Failed to create scripts"
    log INFO "Scripts created successfully with proper permissions"
    echo -e "${GREEN}${BOLD}✓${RESET} Backup and maintenance scripts installed"
}

# Setup cron jobs for backup
setup_cron() {
    log INFO "Setting up cron jobs for automated backups..."

    if ! command -v crontab &>/dev/null; then
        log WARNING "crontab command not found, skipping automated backup setup"
        echo -e "${YELLOW}${BOLD}⚠ crontab command not found, skipping automated backup setup${RESET}"
        echo -e "${YELLOW}To set up automated backups later, install cron and run:${RESET}"
        echo -e "${YELLOW}  (crontab -l 2>/dev/null || true; echo \"0 3 * * * $INSTALL_DIR/backup.sh backup daily\") | crontab -${RESET}"
        echo -e "${YELLOW}  (crontab -l 2>/dev/null || true; echo \"0 2 1 * * $INSTALL_DIR/backup.sh backup monthly\") | crontab -${RESET}"
        return 0
    fi

    # Check if cron entry already exists
    if crontab -l 2>/dev/null | grep -q "$INSTALL_DIR/backup.sh"; then
        log INFO "Cron job for backup already exists"
        echo -e "${YELLOW}Backup cron jobs already exist. Skipping...${RESET}"
        return 0
    fi

    echo -e "${CYAN}Setting up daily and monthly backup cron jobs...${RESET}"

    if $VERBOSE; then
        log INFO "Adding cron job: 0 3 * * * $INSTALL_DIR/backup.sh backup daily"
        log INFO "Adding cron job: 0 2 1 * * $INSTALL_DIR/backup.sh backup monthly"
    fi

    (crontab -l 2>/dev/null || true; echo "0 3 * * * $INSTALL_DIR/backup.sh backup daily") | crontab -
    (crontab -l 2>/dev/null || true; echo "0 2 1 * * $INSTALL_DIR/backup.sh backup monthly") | crontab -

    validate "cron jobs" "crontab -l | grep -q backup.sh" "Failed to set up cron jobs"
    log INFO "Cron jobs set up successfully"
    echo -e "${GREEN}${BOLD}✓${RESET} Automated backup schedule configured"
}

# Setup SSL configuration files
setup_ssl_config() {
    show_progress "Setting Up SSL Configuration Files"

    log INFO "Setting up SSL configuration files..."

    # Copy SSL config template if it exists
    if [ -f "ssl-config.conf.template" ]; then
        cp ssl-config.conf.template "$INSTALL_DIR/ssl-config.conf.template"
        log INFO "Copied SSL configuration template"
        echo -e "${GREEN}${BOLD}✓${RESET} SSL configuration template installed"
    else
        log WARNING "SSL configuration template not found"
        echo -e "${YELLOW}SSL configuration template not found. SSL setup may be incomplete.${RESET}"
    fi

    # Copy SSL README if it exists
    if [ -f "SSL-README.md" ]; then
        cp SSL-README.md "$INSTALL_DIR/SSL-README.md"
        log INFO "Copied SSL README"
    fi

    # Copy direct SSL config if it exists
    if [ -f "direct-ssl-config.conf" ]; then
        cp direct-ssl-config.conf "$INSTALL_DIR/direct-ssl-config.conf"
        log INFO "Copied direct SSL configuration"
    fi

    # Ask if we should create and set up SSL now
    if [ -f "ssl-config.conf.template" ] && [ -f "ssl-setup.sh" ]; then
        echo -e "${CYAN}${BOLD}SSL Configuration${RESET}"
        echo -e "${CYAN}Odoo can be configured with SSL/HTTPS for secure access.${RESET}"

        if confirm "Do you want to set up SSL/HTTPS during installation?"; then
            # Copy template to actual config
            cp ssl-config.conf.template "$INSTALL_DIR/ssl-config.conf"
            log INFO "Created SSL configuration from template"

            # Prompt for domain
            echo -e "${CYAN}Please enter the domain name for SSL:${RESET}"
            read -r ssl_domain

            if [ -n "$ssl_domain" ]; then
                # Update domain in config
                sed -i "s/DOMAIN=example.com/DOMAIN=$ssl_domain/" "$INSTALL_DIR/ssl-config.conf"
                sed -i "s/WILDCARD_DOMAIN=\*\.example\.com/WILDCARD_DOMAIN=*.$ssl_domain/" "$INSTALL_DIR/ssl-config.conf"
                log INFO "Updated SSL configuration with domain: $ssl_domain"
                echo -e "${GREEN}${BOLD}✓${RESET} SSL configuration updated with domain: $ssl_domain"
            else
                log WARNING "No domain provided for SSL configuration"
                echo -e "${YELLOW}No domain provided. Using default values in SSL config.${RESET}"
            fi

            # Prompt for email
            echo -e "${CYAN}Please enter the email for Let's Encrypt certificates:${RESET}"
            read -r ssl_email

            if [ -n "$ssl_email" ]; then
                # Update email in config
                sed -i "s/CERT_EMAIL=admin@example.com/CERT_EMAIL=$ssl_email/" "$INSTALL_DIR/ssl-config.conf"
                log INFO "Updated SSL configuration with email: $ssl_email"
                echo -e "${GREEN}${BOLD}✓${RESET} SSL configuration updated with email: $ssl_email"
            else
                log WARNING "No email provided for SSL certificates"
                echo -e "${YELLOW}No email provided. Using default values in SSL config.${RESET}"
            fi
        else
            log INFO "SSL setup deferred. Can be set up later."
            echo -e "${YELLOW}SSL setup will be skipped. You can set it up later by running:${RESET}"
            echo -e "${CYAN}$INSTALL_DIR/ssl-setup.sh${RESET}"
        fi
    fi

    log INFO "SSL configuration files setup completed"
}

# Initialize database
initialize_database() {
    show_progress "Initializing Odoo Database"

    log INFO "Initializing Odoo database..."
    echo -e "${CYAN}Initializing the Odoo database. This may take a few minutes...${RESET}"

    # Wait for services to be ready
    echo -e "${YELLOW}Waiting for services to start...${RESET}"
    sleep 10

    # Create the first database using Odoo's API
    echo -e "${CYAN}Creating initial database...${RESET}"
    curl -s -X POST \
        -H "Content-Type: application/json" \
        -d '{
            "jsonrpc": "2.0",
            "method": "call",
            "params": {
                "master_pwd": "'$ADMIN_PASS'",
                "name": "'$DB_NAME'",
                "login": "admin",
                "password": "'$ADMIN_PASS'",
                "lang": "en_US",
                "country_code": "es"
            }
        }' \
        http://localhost:8069/web/database/create > /dev/null

    validate "Database creation" "curl -s http://localhost:8069/web/database/selector" "Failed to create database"

    log INFO "Database initialized and ready to use"
    echo -e "${GREEN}${BOLD}✓${RESET} Database initialized successfully"
}

# Check service health
check_service_health() {
    show_progress "Verifying Services"

    log INFO "Checking service health..."
    echo -e "${CYAN}Checking if Odoo services are running properly...${RESET}"

    local max_attempts=30
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        echo -ne "${YELLOW}Checking services ($attempt/$max_attempts)...${RESET}\r"

        # Check if database is accessible
        if docker exec $DB_CONTAINER psql -U $DB_USER -d $DB_NAME -c "SELECT 1" >/dev/null 2>&1; then
            # Check if Odoo web interface is responding
            if curl -s http://localhost:8069/web/database/selector > /dev/null; then
                echo -e "\n${GREEN}${BOLD}✓${RESET} ${GREEN}Odoo is fully operational${RESET}"
                log INFO "Odoo is fully operational"
                return 0
            fi
        fi

        sleep 2
        attempt=$((attempt + 1))
    done

    log ERROR "Services failed to become ready"
    echo -e "\n${RED}${BOLD}⚠ Services failed to start properly${RESET}"
    return 1
}

# Verify installation
verify_installation() {
    show_progress "Verifying Installation"

    log INFO "Verifying installation..."
    echo -e "${CYAN}Performing final verification checks...${RESET}"

    # Check database existence and content
    echo -ne "${YELLOW}Checking database...${RESET}\r"
    local db_check=$(docker exec $DB_CONTAINER psql -U $DB_USER -d $DB_NAME -c "SELECT COUNT(*) FROM ir_module_module WHERE state = 'installed'" -t 2>/dev/null)

    if [ $? -ne 0 ] || [ -z "$db_check" ]; then
        log ERROR "Database verification failed"
        echo -e "${RED}${BOLD}⚠ Database verification failed${RESET}"
        return 1
    else
        echo -e "${GREEN}${BOLD}✓${RESET} Database verification successful. $(echo $db_check | xargs) modules installed."
    fi

    # Check Odoo web access
    echo -ne "${YELLOW}Checking web interface...${RESET}\r"
    if ! curl -s http://localhost:8069/web/login | grep -q "Odoo"; then
        log ERROR "Web interface verification failed"
        echo -e "${RED}${BOLD}⚠ Web interface verification failed${RESET}"
        return 1
    else
        echo -e "${GREEN}${BOLD}✓${RESET} Web interface is accessible"
    fi

    log INFO "Installation verified successfully"
    echo -e "${GREEN}${BOLD}✓${RESET} All verification checks passed"
    return 0
}

# Start Docker containers
start_containers() {
    show_progress "Starting Docker Containers"

    log INFO "Starting Docker containers..."
    cd "$INSTALL_DIR"

    # Pull images
    log INFO "Pulling Docker images..."
    echo -e "${CYAN}Pulling Docker images...${RESET}"
    if command -v docker-compose &>/dev/null; then
        docker-compose pull
    else
        docker compose pull
    fi

    # Start containers
    log INFO "Starting containers..."
    echo -e "${CYAN}Starting containers...${RESET}"
    if command -v docker-compose &>/dev/null; then
        docker-compose up -d
    else
        docker compose up -d
    fi

    # Wait for services to be ready
    log INFO "Waiting for services to start..."
    echo -e "${YELLOW}Waiting for services to initialize...${RESET}"
    sleep 10

    # Validate containers
    validate "Odoo container" "docker ps | grep -q '$CONTAINER_NAME'" "Odoo container failed to start"
    validate "PostgreSQL container" "docker ps | grep -q '$DB_CONTAINER'" "PostgreSQL container failed to start"

    echo -e "${GREEN}${BOLD}✓${RESET} Docker containers started successfully"
}

# Show completion message
show_completion() {
    echo -e "\n${BG_GREEN}${WHITE}${BOLD} INSTALLATION COMPLETE ${RESET}\n"
    echo -e "${GREEN}${BOLD}Odoo 17 has been successfully installed for {client_name}!${RESET}"
    echo -e "${CYAN}${BOLD}You can access Odoo at:${RESET}"
    echo -e "  ${BOLD}HTTP:${RESET}  http://$(hostname -I | awk '{print $1}'):8069"

    if [ -f "$INSTALL_DIR/ssl-config.conf" ]; then
        # Extract domain from SSL config
        source "$INSTALL_DIR/ssl-config.conf"
        if [ -n "$DOMAIN" ]; then
            echo -e "  ${BOLD}HTTPS:${RESET} https://$DOMAIN"
        fi
    fi

    echo -e "\n${CYAN}${BOLD}Login Credentials:${RESET}"
    echo -e "  ${BOLD}Username:${RESET} admin"
    echo -e "  ${BOLD}Password:${RESET} {client_password}"
    echo -e "  ${BOLD}Master Password:${RESET} {client_password}"

    echo -e "\n${CYAN}${BOLD}Installation Directory:${RESET} $INSTALL_DIR"
    echo -e "${CYAN}${BOLD}Log File:${RESET} $LOG_FILE"

    echo -e "\n${CYAN}${BOLD}Useful Commands:${RESET}"
    echo -e "  ${YELLOW}View Logs:${RESET}          ${DIM}docker logs -f $CONTAINER_NAME${RESET}"
    echo -e "  ${YELLOW}Restart Odoo:${RESET}       ${DIM}cd $INSTALL_DIR && docker-compose restart web${RESET}"
    echo -e "  ${YELLOW}Stop Odoo:${RESET}          ${DIM}cd $INSTALL_DIR && docker-compose down${RESET}"
    echo -e "  ${YELLOW}Start Odoo:${RESET}         ${DIM}cd $INSTALL_DIR && docker-compose up -d${RESET}"
    echo -e "  ${YELLOW}Backup Database:${RESET}    ${DIM}$INSTALL_DIR/backup.sh backup${RESET}"

    if [ -f "$INSTALL_DIR/ssl-setup.sh" ]; then
        echo -e "  ${YELLOW}Configure SSL:${RESET}      ${DIM}$INSTALL_DIR/ssl-setup.sh${RESET}"
    fi

    echo -e "\n${GREEN}${BOLD}Thank you for using Odoo 17!${RESET}\n"
}

# Main installation process
main() {
    # Display banner
    show_banner

    # Create log directory if it doesn't exist
    mkdir -p "$(dirname "$TEMP_LOG")"

    log INFO "Starting Odoo 17 installation for {client_name}"

    # Analyze system and show summary
    analyze_system
    show_summary

    # Perform installation
    check_prerequisites
    create_directories
    extract_enterprise
    create_backup_script
    setup_cron
    setup_ssl_config
    start_containers
    initialize_database
    check_service_health
    verify_installation

    # SSL Configuration
    if [ -f "$INSTALL_DIR/ssl-config.conf" ] && [ -f "$INSTALL_DIR/ssl-setup.sh" ]; then
        show_progress "Configuring SSL/HTTPS"

        log INFO "Setting up SSL/HTTPS..."
        echo -e "${CYAN}Setting up SSL/HTTPS...${RESET}"
        chmod +x "$INSTALL_DIR/ssl-setup.sh"

        # Run SSL setup script
        cd "$INSTALL_DIR"
        ./ssl-setup.sh

        if [ $? -eq 0 ]; then
            log INFO "SSL setup completed successfully"
            echo -e "${GREEN}${BOLD}✓${RESET} SSL/HTTPS configured successfully"
        else
            log WARNING "SSL setup encountered issues, check ssl-setup.log for details"
            echo -e "${YELLOW}${BOLD}⚠ SSL setup encountered issues.${RESET}"
            echo -e "${YELLOW}Check $INSTALL_DIR/logs/ssl-setup.log for details.${RESET}"
        fi
    else
        log INFO "SSL configuration files not found, skipping SSL setup"
        echo -e "${YELLOW}SSL configuration files not found, skipping SSL setup.${RESET}"
        echo -e "${YELLOW}To set up SSL later, copy ssl-config.conf.template to ssl-config.conf, edit it, and run ./ssl-setup.sh${RESET}"
    fi

    log INFO "Starting Docker containers automatically for plug-and-play experience"
    echo -e "${CYAN}Starting Docker containers...${RESET}"
    cd "$INSTALL_DIR" && docker-compose up -d
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Docker containers started successfully!${RESET}"
        echo -e "${GREEN}You can access Odoo at http://localhost:{odoo_port}${RESET}"
    else
        echo -e "${RED}Failed to start Docker containers. Please check the logs.${RESET}"
        echo -e "${YELLOW}You can manually start them with: cd $INSTALL_DIR && docker-compose up -d${RESET}"
    fi
    
    log INFO "Installation completed successfully"
    show_completion
}

# Run main function
main                                                                                        