#!/bin/bash

# Odoo 17 Installation Script for {client_name}
# Created: $(date)

# Process command line arguments
VERBOSE=false
while getopts "v" opt; do
  case $opt in
    v)
      VERBOSE=true
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      ;;
  esac
done

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

# Display usage
display_usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -v    Enable verbose debugging output"
    echo ""
    exit 1
}

# Define log colors
LOG_COLOR_INFO="\033[0m"      # Default color
LOG_COLOR_WARNING="\033[33m"  # Yellow
LOG_COLOR_ERROR="\033[31m"    # Red
LOG_COLOR_DEBUG="\033[90m"    # Gray
LOG_COLOR_SUCCESS="\033[32m"  # Green
LOG_COLOR_RESET="\033[0m"

# Enhanced logging function that replaces the old log()
log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local color=""
    
    # Add log entry to log file
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    
    # Only display on console if not called by another logging function
    # or if verbose mode is enabled for DEBUG level
    if [[ "$level" != "DEBUG" ]] || [[ "$VERBOSE" == "true" && "$level" == "DEBUG" ]]; then
        case $level in
            INFO)     color=$LOG_COLOR_INFO ;;
            WARNING)  color=$LOG_COLOR_WARNING ;;
            ERROR)    color=$LOG_COLOR_ERROR ;;
            DEBUG)    color=$LOG_COLOR_DEBUG ;;
            SUCCESS)  color=$LOG_COLOR_SUCCESS ;;
            *)        color=$LOG_COLOR_INFO ;;
        esac
        
        echo -e "${color}[$level] $message${LOG_COLOR_RESET}"
    fi
}

INFO() {
    log "INFO" "$1"
}

WARNING() {
    log "WARNING" "$1"
}

ERROR() {
    log "ERROR" "$1"
}

DEBUG() {
    if [ "$VERBOSE" = true ]; then
        log "DEBUG" "$1"
        echo -e "\033[90m[DEBUG] $1\033[0m"  # Gray color for debug output
    fi
}

# Display script header
echo "===================================================="
echo "           Odoo 17 Enterprise Installation"
echo "                  {client_name}"
echo "===================================================="
echo ""
if [ "$VERBOSE" = true ]; then
    echo "Verbose mode enabled. Detailed debug logs will be displayed."
    echo ""
fi

# Diagnostic info to verify template substitution is working correctly
echo "==== DIAGNOSTIC INFO FOR SETUP ===="
echo "INSTALL_DIR: $INSTALL_DIR"
echo "DB_NAME: $DB_NAME"
echo "CONTAINER_NAME: $CONTAINER_NAME"
# We do not log DB_PASS for security
echo "DB_PASS length: ${#DB_PASS} characters"
echo "==== END DIAGNOSTIC INFO ===="

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
        docker compose down -v 2>/dev/null || true
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

# Function to install Docker and Docker Compose
install_docker() {
    show_progress "Installing Docker"
    log INFO "Installing Docker and Docker Compose..."
    
    # Detect OS
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        OS_NAME="$ID"
        OS_VERSION="$VERSION_ID"
        OS_FAMILY="$ID_LIKE"
        log INFO "Detected OS: $OS_NAME $OS_VERSION (family: $OS_FAMILY)"
    else
        log ERROR "Could not detect OS distribution"
        echo -e "${RED}${BOLD}⚠ Could not detect OS distribution${RESET}"
        echo -e "${YELLOW}Please install Docker manually following the official instructions:${RESET}"
        echo -e "${YELLOW}https://docs.docker.com/engine/install/${RESET}"
        exit 1
    fi
    
    # Install Docker based on OS distribution
    case "$OS_NAME" in
        ubuntu|debian|linuxmint)
            log INFO "Installing Docker on Debian/Ubuntu-based system"
            echo -e "${CYAN}Installing Docker for $OS_NAME...${RESET}"
            
            # Update package lists
            echo -e "${YELLOW}Updating package lists...${RESET}"
            sudo apt-get update
            
            # Install prerequisites
            echo -e "${YELLOW}Installing prerequisites...${RESET}"
            sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common gnupg
            
            # Add Docker GPG key and repository
            curl -fsSL https://download.docker.com/linux/$OS_NAME/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/$OS_NAME $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            
            # Update package lists again
            sudo apt-get update
            
            # Install Docker
            echo -e "${YELLOW}Installing Docker...${RESET}"
            sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            
            # Enable and start Docker service
            sudo systemctl enable docker
            sudo systemctl start docker
            ;;
            
        centos|rhel|fedora|rocky|almalinux)
            log INFO "Installing Docker on RHEL/CentOS-based system"
            echo -e "${CYAN}Installing Docker for $OS_NAME...${RESET}"
            
            # Install prerequisites
            sudo yum install -y yum-utils
            
            # Add Docker repository
            sudo yum-config-manager --add-repo https://download.docker.com/linux/$OS_NAME/docker-ce.repo
            
            # Install Docker
            echo -e "${YELLOW}Installing Docker...${RESET}"
            sudo yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            
            # Enable and start Docker service
            sudo systemctl enable docker
            sudo systemctl start docker
            ;;
            
        *)
            log WARNING "Unsupported OS distribution: $OS_NAME"
            echo -e "${YELLOW}${BOLD}⚠ Unsupported OS distribution: $OS_NAME${RESET}"
            echo -e "${YELLOW}Would you like to try the generic Docker installation method?${RESET}"
            
            if confirm "Try generic Docker installation method?" "Y"; then
                echo -e "${CYAN}Installing Docker using convenience script...${RESET}"
                curl -fsSL https://get.docker.com -o get-docker.sh
                sudo sh get-docker.sh
                sudo systemctl enable docker
                sudo systemctl start docker
            else
                echo -e "${RED}Docker installation skipped. Please install Docker manually.${RESET}"
                echo -e "${YELLOW}https://docs.docker.com/engine/install/${RESET}"
                exit 1
            fi
            ;;
    esac
    
    # Install Docker Compose if needed
    if ! command -v docker-compose &>/dev/null && ! docker compose version &>/dev/null; then
        log INFO "Installing Docker Compose"
        echo -e "${CYAN}Installing Docker Compose...${RESET}"
        
        # Default to using Docker Compose Plugin
        sudo apt-get install -y docker-compose-plugin || sudo yum install -y docker-compose-plugin || {
            # Fallback to standalone Docker Compose
            COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
            sudo curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
            sudo chmod +x /usr/local/bin/docker-compose
        }
    fi
    
    # Add user to docker group
    if ! groups | grep -q docker; then
        log INFO "Adding user to docker group"
        echo -e "${YELLOW}Adding your user to the docker group...${RESET}"
        sudo usermod -aG docker $USER
        echo -e "${GREEN}User added to docker group.${RESET}"
        echo -e "${YELLOW}Note: You may need to log out and log back in for the group changes to take effect.${RESET}"
        echo -e "${YELLOW}For now, you may need to use 'sudo' with Docker commands.${RESET}"
    fi
    
    # Verify installation
    if command -v docker &>/dev/null; then
        DOCKER_VERSION=$(docker --version 2>/dev/null | cut -d' ' -f3 | tr -d ',' || echo "Unknown")
        log INFO "Docker installed successfully: $DOCKER_VERSION"
        echo -e "${GREEN}${BOLD}✓${RESET} Docker installed successfully: $DOCKER_VERSION"
    else
        log ERROR "Docker installation failed"
        echo -e "${RED}${BOLD}⚠ Docker installation failed${RESET}"
        exit 1
    fi
    
    if command -v docker-compose &>/dev/null; then
        COMPOSE_VERSION=$(docker-compose --version 2>/dev/null | cut -d' ' -f3 | tr -d ',' || echo "Unknown")
        log INFO "Docker Compose installed successfully (standalone): $COMPOSE_VERSION"
        echo -e "${GREEN}${BOLD}✓${RESET} Docker Compose installed successfully: $COMPOSE_VERSION"
    elif docker compose version &>/dev/null; then
        COMPOSE_VERSION=$(docker compose version --short 2>/dev/null || echo "Unknown")
        log INFO "Docker Compose installed successfully (plugin): $COMPOSE_VERSION"
        echo -e "${GREEN}${BOLD}✓${RESET} Docker Compose installed successfully: $COMPOSE_VERSION"
    else
        log ERROR "Docker Compose installation failed"
        echo -e "${RED}${BOLD}⚠ Docker Compose installation failed${RESET}"
        exit 1
    fi
    
    echo -e "${GREEN}${BOLD}Docker and Docker Compose installed successfully!${RESET}"
}

check_docker() {
    log INFO "Checking Docker availability..."
    
    if ! command -v docker &>/dev/null; then
        log WARNING "Docker is not installed"
        echo -e "${YELLOW}${BOLD}⚠ Docker is not installed${RESET}"
        echo -e "${YELLOW}This installation requires Docker to run Odoo.${RESET}"
        
        if confirm "Would you like to install Docker now?" "Y"; then
            install_docker
        else
            log ERROR "Docker installation declined by user"
            echo -e "${RED}Installation cannot proceed without Docker. Exiting.${RESET}"
            echo -e "${YELLOW}You can install Docker manually using:${RESET}"
            echo -e "${YELLOW}https://docs.docker.com/engine/install/${RESET}"
            exit 1
        fi
    fi
    
    if ! command -v docker-compose &>/dev/null && ! docker compose version &>/dev/null; then
        log WARNING "Docker Compose is not installed"
        echo -e "${YELLOW}${BOLD}⚠ Docker Compose is not installed${RESET}"
        echo -e "${YELLOW}This installation requires Docker Compose to orchestrate containers.${RESET}"
        
        if confirm "Would you like to install Docker Compose now?" "Y"; then
            # Call the install_docker function to install Docker Compose
            install_docker
        else
            log ERROR "Docker Compose installation declined by user"
            echo -e "${RED}Installation cannot proceed without Docker Compose. Exiting.${RESET}"
            echo -e "${YELLOW}You can install Docker Compose manually using:${RESET}"
            echo -e "${YELLOW}https://docs.docker.com/compose/install/${RESET}"
            exit 1
        fi
    fi
    
    if ! docker info &>/dev/null; then
        log WARNING "Docker daemon is not running"
        echo -e "${YELLOW}${BOLD}⚠ Docker daemon is not running${RESET}"
        
        if confirm "Would you like to start the Docker service now?" "Y"; then
            echo -e "${CYAN}Starting Docker service...${RESET}"
            sudo systemctl start docker
            sudo systemctl enable docker
            
            # Wait for Docker to start
            echo -e "${YELLOW}Waiting for Docker to start...${RESET}"
            sleep 5
            
            if ! docker info &>/dev/null; then
                log ERROR "Failed to start Docker daemon"
                echo -e "${RED}${BOLD}⚠ Failed to start Docker daemon${RESET}"
                echo -e "${YELLOW}Please start Docker manually:${RESET}"
                echo -e "${YELLOW}sudo systemctl start docker${RESET}"
                exit 1
            else
                log INFO "Docker daemon started successfully"
                echo -e "${GREEN}${BOLD}✓${RESET} Docker daemon started successfully"
            fi
        else
            log ERROR "Docker daemon start declined by user"
            echo -e "${RED}Installation cannot proceed without Docker running. Exiting.${RESET}"
            echo -e "${YELLOW}Start Docker manually with:${RESET}"
            echo -e "${YELLOW}sudo systemctl start docker${RESET}"
            exit 1
        fi
    fi
    
    if ! docker ps &>/dev/null; then
        log WARNING "Current user may not have permission to run Docker"
        echo -e "${YELLOW}${BOLD}⚠ Current user may not have permission to run Docker${RESET}"
        
        if confirm "Would you like to add your user to the docker group?" "Y"; then
            echo -e "${CYAN}Adding user to docker group...${RESET}"
            sudo usermod -aG docker $USER
            echo -e "${GREEN}User added to docker group.${RESET}"
            echo -e "${YELLOW}Note: You may need to log out and log back in for this to take effect.${RESET}"
            echo -e "${YELLOW}For now, the installation will continue with sudo.${RESET}"
        else
            echo -e "${YELLOW}Continuing without adding user to docker group.${RESET}"
            echo -e "${YELLOW}You may need to use sudo for docker commands.${RESET}"
        fi
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
        # This section is now redundant because check_docker() will have installed Docker
        # or exited if user declined installation
        DOCKER_VERSION="Not Installed"
        log WARNING "Docker not detected (should have been installed by check_docker)"
    fi

    # Docker Compose Version
    if command -v docker-compose &>/dev/null; then
        DOCKER_COMPOSE_VERSION=$(docker-compose --version | cut -d' ' -f3 | tr -d ',')
        log INFO "Docker Compose Version: $DOCKER_COMPOSE_VERSION (standalone)"
    elif docker compose version &>/dev/null; then
        DOCKER_COMPOSE_VERSION=$(docker compose version --short)
        log INFO "Docker Compose Version: $DOCKER_COMPOSE_VERSION (plugin)"
    else
        # This section is now redundant because check_docker() will have installed Docker Compose
        # or exited if user declined installation
        DOCKER_COMPOSE_VERSION="Not Installed"
        log WARNING "Docker Compose not detected (should have been installed by check_docker)"
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
    log INFO "Enterprise addons extracted successfully"
    echo -e "${GREEN}${BOLD}✓${RESET} Enterprise addons extracted successfully"
}

# Create backup script
create_backup_script() {
    show_progress "Setting Up Backup and Maintenance Scripts"

    log INFO "Creating scripts..."

    # Define script paths - get current script directory
    local CURRENT_DIR=$(pwd)
    local script_files=("backup.sh" "staging.sh" "git_panel.sh" "ssl-setup.sh")
    
    for script in "${script_files[@]}"; do
        if [ -f "$CURRENT_DIR/$script" ]; then
            # Check if source and destination are the same file
            if [ "$(realpath "$CURRENT_DIR/$script")" != "$(realpath "$INSTALL_DIR/$script")" ]; then
                cp "$CURRENT_DIR/$script" "$INSTALL_DIR/$script"
                log INFO "Copied $script to installation directory"
            else
                log INFO "Skipped copying $script (source and destination are the same)"
            fi
            
            # Make executable regardless
            chmod +x "$INSTALL_DIR/$script"
        else
            if [ "$script" != "ssl-setup.sh" ]; then  # ssl-setup.sh is optional
                log WARNING "Script $script not found in $CURRENT_DIR"
                echo -e "${YELLOW}${BOLD}⚠ Required script $script not found${RESET}"
            fi
        fi
    done

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

    # Define current directory
    local CURRENT_DIR=$(pwd)
    local ssl_files=("ssl-config.conf.template" "SSL-README.md" "direct-ssl-config.conf" "ssl-setup.sh")
    
    for file in "${ssl_files[@]}"; do
        if [ -f "$CURRENT_DIR/$file" ]; then
            # Check if source and destination are the same file
            if [ "$(realpath "$CURRENT_DIR/$file")" != "$(realpath "$INSTALL_DIR/$file")" ]; then
                cp "$CURRENT_DIR/$file" "$INSTALL_DIR/$file"
                log INFO "Copied $file to installation directory"
            else
                log INFO "Skipped copying $file (source and destination are the same)"
            fi
            
            # Make executable if it's a script
            if [[ "$file" == *.sh ]]; then
                chmod +x "$INSTALL_DIR/$file"
            fi
        else
            log INFO "$file not found in current directory, skipping"
        fi
    done

    # Ask if we should create and set up SSL now
    if [ -f "$INSTALL_DIR/ssl-config.conf.template" ] && [ -f "$INSTALL_DIR/ssl-setup.sh" ]; then
        echo -e "${CYAN}${BOLD}SSL Configuration${RESET}"
        echo -e "${CYAN}Odoo can be configured with SSL/HTTPS for secure access.${RESET}"

        if confirm "Do you want to set up SSL/HTTPS during installation?"; then
            # Copy template to actual config without using cp command, use cat instead
            cat "$INSTALL_DIR/ssl-config.conf.template" > "$INSTALL_DIR/ssl-config.conf"
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

    INFO "Initializing Odoo database..."
    echo -e "${CYAN}Initializing the Odoo database. This may take a few minutes...${RESET}"

    # Wait for services to be ready
    echo -e "${YELLOW}Waiting for services to start...${RESET}"
    sleep 10
    
    DEBUG "Starting database initialization process"
    DEBUG "Target database: $DB_NAME, DB User: $DB_USER"
    DEBUG "Container names - Odoo: $CONTAINER_NAME, PostgreSQL: $DB_CONTAINER"

    # Try to determine the actual password PostgreSQL is using
    local pg_password=$DB_PASS
    DEBUG "Initial password from script variables (length: ${#pg_password} chars)"
    
    local postgres_env_password=$(docker exec $DB_CONTAINER printenv POSTGRES_PASSWORD 2>/dev/null || echo "")
    DEBUG "Container POSTGRES_PASSWORD environment variable detected (length: ${#postgres_env_password} chars)"
    
    if [ -n "$postgres_env_password" ] && [ "$postgres_env_password" != "$DB_PASS" ]; then
        WARNING "POSTGRES_PASSWORD environment variable differs from DB_PASS"
        echo -e "${YELLOW}Container password differs from script variable. Trying container password.${RESET}"
        DEBUG "Using container-provided password instead of script variable"
        pg_password=$postgres_env_password
    fi
    
    # Try authentication with pg_password
    INFO "Testing database connection with detected password"
    DEBUG "Executing psql connection test"
    if ! docker exec -e PGPASSWORD="$pg_password" $DB_CONTAINER psql -h localhost -U $DB_USER -c "SELECT 1" >/dev/null 2>&1; then
        WARNING "Authentication with detected password failed, using hardcoded fallback"
        DEBUG "Connection test failed with primary password"
        
        # Hardcoded test with specific common enterprise passwords as a last resort
        local test_passwords=("epitanen" "odoo" "postgres")
        for test_pass in "${test_passwords[@]}"; do
            DEBUG "Testing fallback password #${#test_pass} chars"
            if docker exec -e PGPASSWORD="$test_pass" $DB_CONTAINER psql -h localhost -U $DB_USER -c "SELECT 1" >/dev/null 2>&1; then
                WARNING "Hardcoded fallback password works! Using it for database operations"
                echo -e "${YELLOW}Found working fallback password. Using it for database operations${RESET}"
                DEBUG "Fallback password authentication successful"
                pg_password=$test_pass
                break
            fi
        done
    else
        INFO "Authentication with detected password successful"
        DEBUG "Primary password authentication successful"
    fi
    
    # Create connection string for easier reuse
    PG_CONN_STRING="-h db -U $DB_USER -p 5432"
    export PGPASSWORD="$pg_password"
    INFO "Using database connection: $PG_CONN_STRING (user=$DB_USER, db=$DB_NAME)"
    DEBUG "PostgreSQL connection string: $PG_CONN_STRING"

    # Step 1: Make sure containers are running
    DEBUG "Ensuring all containers are running"
    cd "$INSTALL_DIR"
    docker compose up -d
    sleep 10
    
    # Show current container status
    if [ "$VERBOSE" = true ]; then
        DEBUG "Current container status:"
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "$CONTAINER_NAME|$DB_CONTAINER" | while read line; do
            DEBUG "Container: $line"
        done
    fi
    
    # Step 2: Clean start - drop existing database if it exists
    INFO "Dropping existing database if it exists"
    DEBUG "Executing DROP DATABASE IF EXISTS command"
    docker_output=$(docker exec -e PGPASSWORD="$pg_password" $DB_CONTAINER psql $PG_CONN_STRING -c "DROP DATABASE IF EXISTS $DB_NAME;" 2>&1)
    DEBUG "DROP DATABASE result: $docker_output"
    sleep 2
    
    # Step 3: Create empty database with owner
    INFO "Creating empty database with correct owner"
    DEBUG "Executing CREATE DATABASE command"
    docker_output=$(docker exec -e PGPASSWORD="$pg_password" $DB_CONTAINER psql $PG_CONN_STRING -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;" 2>&1)
    DEBUG "CREATE DATABASE result: $docker_output"
    sleep 2

    # Step 4: Primary initialization method - use direct Odoo command with full parameters
    INFO "Initializing database schema with Odoo - METHOD 1"
    echo -e "${CYAN}Initializing database schema with Odoo...${RESET}"
    DEBUG "Starting METHOD 1: Direct Odoo initialization with command-line parameters"
    
    # If in verbose mode, capture all Odoo output
    if [ "$VERBOSE" = true ]; then
        DEBUG "Executing Odoo initialization with full output capture:"
        DEBUG "Command: odoo --stop-after-init --init=base,web --without-demo=all --load-language=en_US -d $DB_NAME --db_host=db --db_user=$DB_USER"
        
        # When in verbose mode, redirect output to both terminal and log file
        docker exec -e LOG_LEVEL=debug $CONTAINER_NAME odoo --stop-after-init \
            --init=base,web \
            --without-demo=all \
            --load-language=en_US \
            -d $DB_NAME \
            --db_host=db \
            --db_user=$DB_USER \
            --db_password="$pg_password" 2>&1 | tee -a "$LOG_FILE"
    else
        # Normal mode - just run the command
        docker exec -e LOG_LEVEL=info $CONTAINER_NAME odoo --stop-after-init \
            --init=base,web \
            --without-demo=all \
            --load-language=en_US \
            -d $DB_NAME \
            --db_host=db \
            --db_user=$DB_USER \
            --db_password="$pg_password"
    fi
    
    INIT_RESULT=$?
    DEBUG "METHOD 1 initialization exit code: $INIT_RESULT"
    
    # Check if initialization worked by counting tables
    DEBUG "Verifying database tables after METHOD 1"
    local table_count=$(docker exec -e PGPASSWORD="$pg_password" $DB_CONTAINER psql $PG_CONN_STRING -d $DB_NAME -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public';" -t 2>/dev/null | tr -d '[:space:]')
    DEBUG "Table count after METHOD 1: $table_count"
    
    # List some tables if in verbose mode
    if [ "$VERBOSE" = true ] && [ -n "$table_count" ] && [ "$table_count" -gt 0 ]; then
        DEBUG "Listing first 10 tables in database:"
        table_list=$(docker exec -e PGPASSWORD="$pg_password" $DB_CONTAINER psql $PG_CONN_STRING -d $DB_NAME -c "SELECT table_name FROM information_schema.tables WHERE table_schema='public' LIMIT 10;" -t 2>/dev/null)
        DEBUG "Tables: $table_list"
    fi
    
    if [ "$INIT_RESULT" -eq 0 ] && [ -n "$table_count" ] && [ "$table_count" -gt 20 ]; then
        INFO "Database initialized successfully - METHOD 1 - $table_count tables created"
        echo -e "${GREEN}${BOLD}✓${RESET} Database initialized successfully with $table_count tables"
        DEBUG "METHOD 1 successful - initialization complete"
        return 0
    fi
    
    WARNING "First initialization method failed or incomplete ($table_count tables). Trying METHOD 2..."
    echo -e "${YELLOW}First initialization method failed or incomplete. Trying METHOD 2...${RESET}"
    DEBUG "METHOD 1 failed or incomplete. Table count below threshold or other error."
    
    # Step 5: Alternative Method - Use the Odoo API
    INFO "Using Odoo API to create database - METHOD 2"
    echo -e "${CYAN}Using Odoo API to create database...${RESET}"
    DEBUG "Starting METHOD 2: Database creation through Odoo API"
    
    # First, drop the database again for a clean start
    DEBUG "Dropping database again for clean start"
    docker_output=$(docker exec -e PGPASSWORD="$pg_password" $DB_CONTAINER psql $PG_CONN_STRING -c "DROP DATABASE IF EXISTS $DB_NAME;" 2>&1)
    DEBUG "DROP DATABASE result: $docker_output"
    sleep 2
    
    # Restart web container
    DEBUG "Restarting Odoo web container"
    docker compose restart web
    sleep 15
    
    # Use curl to access the database manager API
    DEBUG "Building API request for database creation"
    DEBUG "API endpoint: http://localhost:8069/web/database/create"
    DEBUG "Using parameters: name=$DB_NAME, login=admin, lang=en_US, country_code=es"
    
    # Prepare API request
    api_request='{
        "jsonrpc": "2.0",
        "method": "call",
        "params": {
            "master_pwd": "'$pg_password'",
            "name": "'$DB_NAME'",
            "login": "admin",
            "password": "'$pg_password'",
            "lang": "en_US",
            "country_code": "es",
            "phone": ""
        }
    }'
    DEBUG "Sending API request to create database"
    
    if [ "$VERBOSE" = true ]; then
        DEBUG "Full API request (redacted passwords):"
        echo "$api_request" | sed 's/"master_pwd": "[^"]*"/"master_pwd": "REDACTED"/g' | sed 's/"password": "[^"]*"/"password": "REDACTED"/g' >> "$LOG_FILE"
        
        # Capture API response in verbose mode
        api_response=$(curl -s -X POST \
            -H "Content-Type: application/json" \
            -d "$api_request" \
            http://localhost:8069/web/database/create)
        
        DEBUG "API response: $api_response"
    else
        # Normal mode - just run the command
        curl -s -X POST \
            -H "Content-Type: application/json" \
            -d "$api_request" \
            http://localhost:8069/web/database/create > /dev/null
    fi
    
    echo -e "${YELLOW}Waiting for database creation to complete...${RESET}"
    DEBUG "Waiting for database creation to complete (30s)"
    sleep 30
    
    # Check if initialization worked by counting tables again
    DEBUG "Verifying database tables after METHOD 2"
    table_count=$(docker exec -e PGPASSWORD="$pg_password" $DB_CONTAINER psql $PG_CONN_STRING -d $DB_NAME -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public';" -t 2>/dev/null | tr -d '[:space:]')
    DEBUG "Table count after METHOD 2: $table_count"
    
    # List some tables if in verbose mode
    if [ "$VERBOSE" = true ] && [ -n "$table_count" ] && [ "$table_count" -gt 0 ]; then
        DEBUG "Listing first 10 tables in database:"
        table_list=$(docker exec -e PGPASSWORD="$pg_password" $DB_CONTAINER psql $PG_CONN_STRING -d $DB_NAME -c "SELECT table_name FROM information_schema.tables WHERE table_schema='public' LIMIT 10;" -t 2>/dev/null)
        DEBUG "Tables: $table_list"
        
        # Check specifically for ir_module_module table
        ir_module_check=$(docker exec -e PGPASSWORD="$pg_password" $DB_CONTAINER psql $PG_CONN_STRING -d $DB_NAME -c "SELECT EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name='ir_module_module');" -t 2>/dev/null | tr -d '[:space:]')
        DEBUG "ir_module_module table exists: $ir_module_check"
        
        if [ "$ir_module_check" = "t" ]; then
            # Count installed modules
            modules_count=$(docker exec -e PGPASSWORD="$pg_password" $DB_CONTAINER psql $PG_CONN_STRING -d $DB_NAME -c "SELECT COUNT(*) FROM ir_module_module WHERE state='installed';" -t 2>/dev/null | tr -d '[:space:]')
            DEBUG "Number of installed modules: $modules_count"
        fi
    fi
    
    if [ -n "$table_count" ] && [ "$table_count" -gt 20 ]; then
        INFO "Database initialized successfully - METHOD 2 - $table_count tables created"
        echo -e "${GREEN}${BOLD}✓${RESET} Database initialized successfully with $table_count tables"
        DEBUG "METHOD 2 successful - initialization complete"
        return 0
    fi
    
    ERROR "Database initialization failed after multiple attempts ($table_count tables)"
    echo -e "${RED}${BOLD}⚠ Database initialization failed after multiple attempts${RESET}"
    DEBUG "Both METHOD 1 and METHOD 2 failed. Database not properly initialized."
    DEBUG "Final table count: $table_count (expected >20)"
    
    # Provide detailed diagnostics if in verbose mode
    if [ "$VERBOSE" = true ]; then
        DEBUG "=== DIAGNOSTIC INFORMATION ==="
        DEBUG "Docker container status:"
        docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "$CONTAINER_NAME|$DB_CONTAINER" >> "$LOG_FILE"
        
        DEBUG "PostgreSQL container logs (last 30 lines):"
        docker logs --tail 30 $DB_CONTAINER >> "$LOG_FILE" 2>&1
        
        DEBUG "Odoo container logs (last 30 lines):"
        docker logs --tail 30 $CONTAINER_NAME >> "$LOG_FILE" 2>&1
        
        DEBUG "Database list:"
        docker exec -e PGPASSWORD="$pg_password" $DB_CONTAINER psql $PG_CONN_STRING -c "\l" >> "$LOG_FILE" 2>&1
        
        DEBUG "Odoo configuration:"
        docker exec $CONTAINER_NAME cat /etc/odoo/odoo.conf >> "$LOG_FILE" 2>&1 || true
        
        DEBUG "Network information:"
        docker network inspect $(docker inspect $CONTAINER_NAME --format '{{range $key, $value := .NetworkSettings.Networks}}{{$key}}{{end}}') >> "$LOG_FILE" 2>&1
        
        DEBUG "=== END DIAGNOSTIC INFORMATION ==="
    fi
    
    echo -e "${YELLOW}Manual intervention required. Please follow these steps:${RESET}"
    echo -e "${YELLOW}1. Visit http://$(hostname -I | awk '{print $1}'):8069/web/database/manager${RESET}"
    echo -e "${YELLOW}2. Choose 'Create Database'${RESET}"
    echo -e "${YELLOW}3. Set Master Password to: $pg_password${RESET}"
    echo -e "${YELLOW}4. Set Database Name to: $DB_NAME${RESET}"
    echo -e "${YELLOW}5. Complete the form and create the database${RESET}"
    
    return 1
}

# Check service health
check_service_health() {
    show_progress "Verifying Services"

    log INFO "Checking service health..."
    echo -e "${CYAN}Checking if Odoo services are running properly...${RESET}"

    # Determine password to use - try our detected password first, then fallbacks
    local pg_password=$1
    if [ -z "$pg_password" ]; then
        # Try to determine working password just like in initialize_database
        pg_password=$DB_PASS
        local postgres_env_password=$(docker exec $DB_CONTAINER printenv POSTGRES_PASSWORD 2>/dev/null || echo "")
        
        if [ -n "$postgres_env_password" ] && [ "$postgres_env_password" != "$pg_password" ]; then
            log INFO "Using POSTGRES_PASSWORD from container environment"
            pg_password=$postgres_env_password
        fi
        
        # Try authentication with pg_password
        if ! docker exec -e PGPASSWORD="$pg_password" $DB_CONTAINER psql -h localhost -U $DB_USER -c "SELECT 1" >/dev/null 2>&1; then
            log WARNING "Testing fallback passwords for service check"
            local test_passwords=("epitanen" "odoo" "postgres")
            for test_pass in "${test_passwords[@]}"; do
                if docker exec -e PGPASSWORD="$test_pass" $DB_CONTAINER psql -h localhost -U $DB_USER -c "SELECT 1" >/dev/null 2>&1; then
                    log WARNING "Using fallback password for service check"
                    pg_password=$test_pass
                    break
                fi
            done
        fi
    fi

    local max_attempts=30
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        echo -ne "${YELLOW}Checking services ($attempt/$max_attempts)...${RESET}\r"

        # Check if database is accessible
        if docker exec -e PGPASSWORD="$pg_password" $DB_CONTAINER psql $PG_CONN_STRING -c "SELECT 1" >/dev/null 2>&1; then
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
    local db_check=$(docker exec -e PGPASSWORD="$DB_PASS" $DB_CONTAINER psql $PG_CONN_STRING -c "SELECT COUNT(*) FROM ir_module_module WHERE state = 'installed'" -t 2>/dev/null)

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
    # Try to get the most accurate password to show
    ACTUAL_PASSWORD=$(docker exec $DB_CONTAINER printenv POSTGRES_PASSWORD 2>/dev/null || echo "$DB_PASS")
    
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
    echo -e "  ${BOLD}Password:${RESET} $ACTUAL_PASSWORD"
    echo -e "  ${BOLD}Master Password:${RESET} $ACTUAL_PASSWORD"

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

# Main execution
main() {
    # Create temporary install log (will be moved to proper location later)
    mkdir -p $(dirname "$TEMP_LOG")
    touch "$TEMP_LOG"
    
    # Display banner
    echo "===================================================="
    echo "           Odoo 17 Enterprise Installation"
    echo "                  {client_name}"
    echo "===================================================="
    if [ "$VERBOSE" = true ]; then
        echo -e "${LOG_COLOR_DEBUG}Verbose debugging mode enabled${LOG_COLOR_RESET}"
        DEBUG "Starting installation process with verbose logging"
    fi
    echo ""
    
    # Start installation
    INFO "Starting installation process (Verbose mode: $VERBOSE)"
    
    # Create folders for log
    mkdir -p $(dirname "$LOG_FILE")
    cat "$TEMP_LOG" > "$LOG_FILE"

    # Show the installation steps
    echo -e "${WHITE}${BOLD}Installation Steps:${RESET}"
    echo -e " ${GRAY}[1/10] Checking Prerequisites${RESET}"
    echo -e " ${GRAY}[2/10] Creating Directory Structure${RESET}"
    echo -e " ${GRAY}[3/10] Extracting Enterprise Addons${RESET}"
    echo -e " ${GRAY}[4/10] Creating Backup Script${RESET}"
    echo -e " ${GRAY}[5/10] Setting up Cron Jobs${RESET}"
    echo -e " ${GRAY}[6/10] Configuring SSL (if applicable)${RESET}"
    echo -e " ${GRAY}[7/10] Starting Docker Containers${RESET}"
    echo -e " ${GRAY}[8/10] Initializing Odoo Database${RESET}"
    echo -e " ${GRAY}[9/10] Verifying Services${RESET}"
    echo -e " ${GRAY}[10/10] Finalizing Installation${RESET}"
    echo ""

    # Perform installation
    check_prerequisites
    create_directories
    extract_enterprise
    create_backup_script
    setup_cron
    setup_ssl_config
    start_containers
    
    # Initialize database and save the working password
    initialize_database
    DB_WORKING_PASSWORD="$pg_password"  # Save the working password detected
    
    DEBUG "Database initialization complete, using password for further operations"
    
    # Use the detected password for remaining functions
    check_service_health "$DB_WORKING_PASSWORD"
    verify_installation
    
    # Show completion message if everything succeeded
    if [ $? -eq 0 ]; then
        show_completion
        INFO "Installation completed successfully"
        DEBUG "All installation steps completed without errors"
    else
        ERROR "Installation failed"
        DEBUG "Installation process failed - check logs for details"
        echo -e "\n${RED}${BOLD}⚠ Installation failed. Please check the log file for details.${RESET}"
        echo -e "Log file: $LOG_FILE"
    fi
}

# Execute main function
main "$@"
