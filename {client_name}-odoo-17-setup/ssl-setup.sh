#!/bin/bash

# Odoo 17 SSL Setup Script
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
TOTAL_STEPS=7  # Update as needed

# Default locations
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SSL_CONFIG_FILE="$SCRIPT_DIR/ssl-config.conf"
ODOO_CONFIG_FILE="$SCRIPT_DIR/config/odoo.conf"
NGINX_CONFIG_DIR="/etc/nginx/conf.d"
NGINX_CONFIG_FILE="$NGINX_CONFIG_DIR/odoo.conf"
LOG_FILE="$SCRIPT_DIR/logs/ssl-setup.log"

# Store system information
SYS_OS=""
SSL_STATUS="Not Configured"
NGINX_STATUS="Not Detected"
CERTBOT_STATUS="Not Detected"
EXISTING_CERTS=""

# Error handling
set -e

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Logging function
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
    
    echo -e "${level_color}[$(date '+%Y-%m-%d %H:%M:%S')] [$level]${RESET} $*" | tee -a "$LOG_FILE"
}

# Display progress
show_progress() {
    STEP=$((STEP + 1))
    echo -e "\n${BLUE}${BOLD}[$STEP/$TOTAL_STEPS]${RESET} ${CYAN}${BOLD}$1${RESET}\n"
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
    echo "   _____   _____   _      "
    echo "  / ____| / ____| | |     "
    echo " | (___  | (___   | |     "
    echo "  \___ \  \___ \  | |     "
    echo "  ____) | ____) | | |____ "
    echo " |_____/ |_____/  |______|"
    echo "                          "
    echo -e "${RESET}"
    echo -e "${CYAN}${BOLD}SSL/HTTPS Setup for Odoo 17${RESET}"
    echo -e "${DIM}Created: $(date)${RESET}"
    echo
}

# Analyze SSL environment
analyze_environment() {
    show_progress "Analyzing Environment"
    
    log INFO "Analyzing SSL environment..."
    
    # Load config first to access settings
    if [ -f "$SSL_CONFIG_FILE" ]; then
        source "$SSL_CONFIG_FILE"
    fi
    
    # Detect OS
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        SYS_OS="$NAME $VERSION_ID"
        log INFO "Detected OS: $SYS_OS"
    else
        SYS_OS="Unknown"
        log WARNING "Could not detect OS distribution"
    fi
    
    # Check for existing SSL certificates
    if [ -d "/etc/letsencrypt/live" ]; then
        EXISTING_CERTS=$(ls -1 /etc/letsencrypt/live/ 2>/dev/null | grep -v "README" || echo "None")
        if [ "$EXISTING_CERTS" != "None" ]; then
            log INFO "Found existing Let's Encrypt certificates: $EXISTING_CERTS"
            echo -e "${YELLOW}${BOLD}Found existing Let's Encrypt certificates:${RESET}"
            for cert in $EXISTING_CERTS; do
                echo -e "  - $cert"
            done
            
            # If domain is set, check if certificate already exists
            if [ -n "$DOMAIN" ] && [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
                echo -e "${GREEN}${BOLD}✓${RESET} Certificate for $DOMAIN already exists"
                SSL_STATUS="Configured (Let's Encrypt)"
            fi
        else
            log INFO "No existing Let's Encrypt certificates found"
        fi
    fi
    
    # Check manual certificates if specified
    if [ "$CERT_PROVIDER" = "manual" ] && [ -n "$SSL_CERT_PATH" ] && [ -n "$SSL_KEY_PATH" ]; then
        if [ -f "$SSL_CERT_PATH" ] && [ -f "$SSL_KEY_PATH" ]; then
            log INFO "Manual certificates found at specified paths"
            echo -e "${GREEN}${BOLD}✓${RESET} Manual certificates found"
            SSL_STATUS="Configured (Manual)"
        else
            log WARNING "Manual certificates specified but not found"
            echo -e "${YELLOW}${BOLD}⚠${RESET} Manual certificates specified but not found:"
            echo -e "  - Certificate: $SSL_CERT_PATH ($([ -f "$SSL_CERT_PATH" ] && echo "Found" || echo "Not found"))"
            echo -e "  - Key: $SSL_KEY_PATH ($([ -f "$SSL_KEY_PATH" ] && echo "Found" || echo "Not found"))"
        fi
    fi
    
    # Check for control panels
    if [ "$HAS_CPANEL" = "auto" ]; then
        if [ -d /usr/local/cpanel ]; then
            HAS_CPANEL=true
            log INFO "Detected cPanel"
            echo -e "${CYAN}${BOLD}✓${RESET} cPanel detected"
        else
            HAS_CPANEL=false
        fi
    fi
    
    if [ "$HAS_PLESK" = "auto" ]; then
        if [ -d /usr/local/psa ]; then
            HAS_PLESK=true
            log INFO "Detected Plesk"
            echo -e "${CYAN}${BOLD}✓${RESET} Plesk detected"
        else
            HAS_PLESK=false
        fi
    fi
    
    # Check if Nginx is installed
    if [ "$NGINX_INSTALLED" = "auto" ]; then
        if command -v nginx >/dev/null 2>&1; then
            NGINX_INSTALLED=true
            NGINX_STATUS="Installed ($(nginx -v 2>&1 | cut -d '/' -f 2))"
            log INFO "Detected Nginx: $NGINX_STATUS"
            echo -e "${GREEN}${BOLD}✓${RESET} Nginx is installed"
        else
            NGINX_INSTALLED=false
            log INFO "Nginx not detected"
            if [ "$SSL_TYPE" = "PROXY" ]; then
                echo -e "${YELLOW}${BOLD}⚠${RESET} Nginx not found. It will be installed"
            fi
        fi
    fi
    
    # Check if Certbot is installed
    if command -v certbot >/dev/null 2>&1; then
        CERTBOT_STATUS="Installed ($(certbot --version 2>&1 | cut -d ' ' -f 2))"
        log INFO "Detected Certbot: $CERTBOT_STATUS"
        echo -e "${GREEN}${BOLD}✓${RESET} Certbot is installed"
    else
        log INFO "Certbot not detected"
        if [ "$CERT_PROVIDER" = "letsencrypt" ]; then
            echo -e "${YELLOW}${BOLD}⚠${RESET} Certbot not found. It will be installed"
        fi
    fi
    
    # Check if port 80 is open (needed for HTTP challenge)
    if [ "$CERT_PROVIDER" = "letsencrypt" ]; then
        if command -v netstat >/dev/null 2>&1; then
            if ! netstat -tuln | grep -q ":80 "; then
                log WARNING "Port 80 is not open. This may be required for Let's Encrypt HTTP challenge"
                echo -e "${YELLOW}${BOLD}⚠${RESET} Port 80 is not open. This may be required for Let's Encrypt HTTP challenge"
            fi
        elif command -v ss >/dev/null 2>&1; then
            if ! ss -tuln | grep -q ":80 "; then
                log WARNING "Port 80 is not open. This may be required for Let's Encrypt HTTP challenge"
                echo -e "${YELLOW}${BOLD}⚠${RESET} Port 80 is not open. This may be required for Let's Encrypt HTTP challenge"
            fi
        fi
    fi
    
    log INFO "Environment analysis complete"
}

# Show SSL configuration summary
show_ssl_summary() {
    echo -e "\n${BG_BLUE}${WHITE}${BOLD} SSL CONFIGURATION SUMMARY ${RESET}\n"
    echo -e "${CYAN}${BOLD}System Information:${RESET}"
    echo -e "  ${BOLD}Operating System:${RESET} $SYS_OS"
    echo -e "  ${BOLD}Nginx Status:${RESET}    $NGINX_STATUS"
    echo -e "  ${BOLD}Certbot Status:${RESET}  $CERTBOT_STATUS"
    echo -e "  ${BOLD}SSL Status:${RESET}      $SSL_STATUS"
    
    echo -e "\n${CYAN}${BOLD}SSL Configuration:${RESET}"
    echo -e "  ${BOLD}SSL Type:${RESET}        $SSL_TYPE"
    echo -e "  ${BOLD}Domain:${RESET}          $DOMAIN"
    echo -e "  ${BOLD}Certificate:${RESET}     $CERT_PROVIDER"
    
    if [ "$USE_WILDCARD" = "true" ] && [ -n "$WILDCARD_DOMAIN" ]; then
        echo -e "  ${BOLD}Wildcard:${RESET}        $WILDCARD_DOMAIN"
    fi
    
    if [ "$CERT_PROVIDER" = "manual" ]; then
        echo -e "  ${BOLD}Certificate Path:${RESET} $SSL_CERT_PATH ($([ -f "$SSL_CERT_PATH" ] && echo "Found" || echo "Not found"))"
        echo -e "  ${BOLD}Key Path:${RESET}         $SSL_KEY_PATH ($([ -f "$SSL_KEY_PATH" ] && echo "Found" || echo "Not found"))"
    fi
    
    if [ "$SSL_TYPE" = "PROXY" ]; then
        echo -e "  ${BOLD}Nginx Config:${RESET}     $NGINX_CONF_PATH"
        echo -e "  ${BOLD}HTTP Redirect:${RESET}    $([ "$REDIRECT_HTTP_TO_HTTPS" = "true" ] && echo "Enabled" || echo "Disabled")"
    fi
    
    echo -e "\n${CYAN}${BOLD}Actions to be performed:${RESET}"
    if [ "$CERT_PROVIDER" = "letsencrypt" ] && [ "$(command -v certbot)" = "" ]; then
        echo -e "  ${YELLOW}⚙${RESET} Install Certbot"
    fi
    
    if [ "$SSL_TYPE" = "PROXY" ] && [ "$NGINX_INSTALLED" = "false" ]; then
        echo -e "  ${YELLOW}⚙${RESET} Install Nginx"
    fi
    
    if [ "$CERT_PROVIDER" = "letsencrypt" ]; then
        echo -e "  ${YELLOW}⚙${RESET} Obtain Let's Encrypt certificate for $DOMAIN"
        if [ "$CERT_AUTO_RENEW" = "true" ]; then
            echo -e "  ${YELLOW}⚙${RESET} Configure automatic certificate renewal"
        fi
    fi
    
    if [ "$SSL_TYPE" = "PROXY" ]; then
        echo -e "  ${YELLOW}⚙${RESET} Configure Nginx as a reverse proxy"
        if [ "$REDIRECT_HTTP_TO_HTTPS" = "true" ]; then
            echo -e "  ${YELLOW}⚙${RESET} Enable HTTP to HTTPS redirection"
        fi
    elif [ "$SSL_TYPE" = "DIRECT" ]; then
        echo -e "  ${YELLOW}⚙${RESET} Configure Odoo for direct SSL handling"
    fi
    
    echo -e "  ${YELLOW}⚙${RESET} Update Odoo configuration for SSL"
    echo -e "  ${YELLOW}⚙${RESET} Restart Odoo service"
    
    echo -e "\nConfiguration log will be saved to: ${UNDERLINE}$LOG_FILE${RESET}\n"
    
    if ! confirm "Do you want to proceed with SSL configuration?"; then
        echo -e "${RED}SSL setup cancelled by user.${RESET}"
        exit 0
    fi
}

# Load SSL configuration
load_ssl_config() {
    show_progress "Loading SSL Configuration"
    
    log INFO "Loading SSL configuration from $SSL_CONFIG_FILE"
    if [ ! -f "$SSL_CONFIG_FILE" ]; then
        log ERROR "SSL configuration file not found: $SSL_CONFIG_FILE"
        echo -e "${BG_RED}${WHITE}${BOLD} ERROR ${RESET} SSL configuration file not found: $SSL_CONFIG_FILE"
        
        if [ -f "$SCRIPT_DIR/ssl-config.conf.template" ]; then
            echo -e "${YELLOW}A template configuration file is available at:${RESET}"
            echo -e "  $SCRIPT_DIR/ssl-config.conf.template"
            
            if confirm "Would you like to create a configuration file from the template?"; then
                cp "$SCRIPT_DIR/ssl-config.conf.template" "$SSL_CONFIG_FILE"
                log INFO "Created SSL configuration from template"
                
                echo -e "${CYAN}Please provide the domain name for SSL:${RESET}"
                read -r ssl_domain
                
                if [ -n "$ssl_domain" ]; then
                    sed -i "s/DOMAIN=example.com/DOMAIN=$ssl_domain/" "$SSL_CONFIG_FILE"
                    sed -i "s/WILDCARD_DOMAIN=\*\.example\.com/WILDCARD_DOMAIN=*.$ssl_domain/" "$SSL_CONFIG_FILE"
                    log INFO "Updated SSL configuration with domain: $ssl_domain"
                fi
                
                echo -e "${CYAN}Please provide an email address for Let's Encrypt:${RESET}"
                read -r ssl_email
                
                if [ -n "$ssl_email" ]; then
                    sed -i "s/CERT_EMAIL=admin@example.com/CERT_EMAIL=$ssl_email/" "$SSL_CONFIG_FILE"
                    log INFO "Updated SSL configuration with email: $ssl_email"
                fi
                
                echo -e "${GREEN}${BOLD}✓${RESET} Configuration file created. Review $SSL_CONFIG_FILE for more options"
                
                # Ask if user wants to edit the file before proceeding
                if confirm "Would you like to edit the configuration file before proceeding?"; then
                    # Try to find a suitable editor
                    for editor in nano vim vi editor; do
                        if command -v $editor >/dev/null 2>&1; then
                            $editor "$SSL_CONFIG_FILE"
                            break
                        fi
                    done
                    log INFO "Configuration file edited by user"
                fi
            else
                log ERROR "No configuration file available. Cannot proceed"
                echo -e "${RED}SSL setup cancelled. No configuration file available.${RESET}"
                exit 1
            fi
        else
            log ERROR "No template configuration file found. Cannot proceed"
            echo -e "${RED}SSL setup cancelled. No template configuration file found.${RESET}"
            exit 1
        fi
    fi
    
    # Source the config file
    source "$SSL_CONFIG_FILE"
    
    # Validate required parameters
    if [ -z "$SSL_TYPE" ] || [ -z "$DOMAIN" ]; then
        log ERROR "Required configuration missing (SSL_TYPE or DOMAIN)"
        echo -e "${BG_RED}${WHITE}${BOLD} ERROR ${RESET} Required configuration missing:"
        
        if [ -z "$SSL_TYPE" ]; then
            echo -e "${RED}SSL_TYPE not defined in $SSL_CONFIG_FILE${RESET}"
        fi
        
        if [ -z "$DOMAIN" ]; then
            echo -e "${RED}DOMAIN not defined in $SSL_CONFIG_FILE${RESET}"
        fi
        
        echo -e "${YELLOW}Please edit $SSL_CONFIG_FILE and try again.${RESET}"
        exit 1
    fi
    
    # Validate SSL type
    if [ "$SSL_TYPE" != "PROXY" ] && [ "$SSL_TYPE" != "DIRECT" ]; then
        log ERROR "Invalid SSL_TYPE value: $SSL_TYPE (must be PROXY or DIRECT)"
        echo -e "${BG_RED}${WHITE}${BOLD} ERROR ${RESET} Invalid SSL_TYPE value: $SSL_TYPE"
        echo -e "${YELLOW}SSL_TYPE must be set to either 'PROXY' or 'DIRECT' in $SSL_CONFIG_FILE${RESET}"
        exit 1
    fi
    
    log INFO "SSL configuration loaded successfully"
    echo -e "${GREEN}${BOLD}✓${RESET} SSL configuration loaded successfully"
}

# Detect environment (OS, control panels, etc.)
detect_environment() {
    log INFO "Detecting environment..."
    
    # Detect Linux distribution
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        OS_NAME=$NAME
        OS_VERSION=$VERSION_ID
        log INFO "Detected OS: $OS_NAME $OS_VERSION"
    else
        log WARNING "Could not detect OS distribution"
        OS_NAME="Unknown"
        OS_VERSION="Unknown"
    fi
    
    # Detect control panels
    if [ "$HAS_CPANEL" = "auto" ]; then
        if [ -d /usr/local/cpanel ]; then
            HAS_CPANEL=true
            log INFO "Detected cPanel"
        else
            HAS_CPANEL=false
        fi
    fi
    
    if [ "$HAS_PLESK" = "auto" ]; then
        if [ -d /usr/local/psa ]; then
            HAS_PLESK=true
            log INFO "Detected Plesk"
        else
            HAS_PLESK=false
        fi
    fi
    
    # Detect existing Nginx
    if [ "$NGINX_INSTALLED" = "auto" ]; then
        if command -v nginx >/dev/null 2>&1; then
            NGINX_INSTALLED=true
            log INFO "Detected Nginx"
        else
            NGINX_INSTALLED=false
        fi
    fi
    
    log INFO "Environment detection complete"
}

# Install required dependencies
install_dependencies() {
    show_progress "Installing Dependencies"
    
    log INFO "Installing required dependencies..."
    
    # Install certbot for Let's Encrypt certificates
    if [ "$CERT_PROVIDER" = "letsencrypt" ]; then
        if ! command -v certbot >/dev/null 2>&1; then
            log INFO "Installing Certbot for Let's Encrypt..."
            echo -e "${CYAN}Installing Certbot for Let's Encrypt certificates...${RESET}"
            
            if [ -f /etc/debian_version ]; then
                echo -e "${YELLOW}Using apt package manager...${RESET}"
                apt-get update
                apt-get install -y certbot
                if [ "$SSL_TYPE" = "PROXY" ] && [ "$NGINX_INSTALLED" = "true" ]; then
                    apt-get install -y python3-certbot-nginx
                fi
            elif [ -f /etc/redhat-release ]; then
                echo -e "${YELLOW}Using yum package manager...${RESET}"
                yum install -y epel-release
                yum install -y certbot
                if [ "$SSL_TYPE" = "PROXY" ] && [ "$NGINX_INSTALLED" = "true" ]; then
                    yum install -y python3-certbot-nginx
                fi
            else
                log WARNING "Unknown distribution, trying snap for Certbot..."
                echo -e "${YELLOW}Unknown distribution, trying snap for Certbot installation...${RESET}"
                snap install certbot --classic
            fi
            
            # Verify certbot installation
            if ! command -v certbot >/dev/null 2>&1; then
                log ERROR "Failed to install Certbot"
                echo -e "${BG_RED}${WHITE}${BOLD} ERROR ${RESET} Failed to install Certbot"
                echo -e "${RED}Try installing Certbot manually:${RESET}"
                echo -e "${DIM}https://certbot.eff.org/instructions${RESET}"
                exit 1
            fi
            log INFO "Certbot installed successfully"
            echo -e "${GREEN}${BOLD}✓${RESET} Certbot installed successfully"
        else
            log INFO "Certbot is already installed"
            echo -e "${GREEN}${BOLD}✓${RESET} Certbot is already installed: $(certbot --version | cut -d ' ' -f 2)"
        fi
    fi
    
    # Install Nginx if needed
    if [ "$SSL_TYPE" = "PROXY" ] && [ "$NGINX_INSTALLED" = "false" ]; then
        log INFO "Installing Nginx..."
        echo -e "${CYAN}Installing Nginx web server...${RESET}"
        
        if [ -f /etc/debian_version ]; then
            echo -e "${YELLOW}Using apt package manager...${RESET}"
            apt-get update
            apt-get install -y nginx
        elif [ -f /etc/redhat-release ]; then
            echo -e "${YELLOW}Using yum package manager...${RESET}"
            yum install -y nginx
        else
            log ERROR "Unknown distribution, cannot install Nginx automatically"
            echo -e "${BG_RED}${WHITE}${BOLD} ERROR ${RESET} Cannot install Nginx automatically on this distribution"
            echo -e "${RED}Try installing Nginx manually:${RESET}"
            echo -e "${DIM}https://nginx.org/en/docs/install.html${RESET}"
            exit 1
        fi
        
        # Verify Nginx installation
        if ! command -v nginx >/dev/null 2>&1; then
            log ERROR "Failed to install Nginx"
            echo -e "${BG_RED}${WHITE}${BOLD} ERROR ${RESET} Failed to install Nginx"
            exit 1
        fi
        
        # Start and enable Nginx
        echo -e "${YELLOW}Starting and enabling Nginx service...${RESET}"
        systemctl start nginx
        systemctl enable nginx
        
        NGINX_INSTALLED=true
        log INFO "Nginx installed successfully"
        echo -e "${GREEN}${BOLD}✓${RESET} Nginx installed successfully"
    elif [ "$SSL_TYPE" = "PROXY" ] && [ "$NGINX_INSTALLED" = "true" ]; then
        log INFO "Nginx is already installed"
        echo -e "${GREEN}${BOLD}✓${RESET} Nginx is already installed: $(nginx -v 2>&1 | cut -d '/' -f 2)"
    fi
    
    log INFO "All dependencies installed successfully"
}

# Generate and install SSL certificates
get_certificates() {
    show_progress "Obtaining SSL Certificates"
    
    log INFO "Setting up SSL certificates..."
    
    # Skip if using panel-managed SSL
    if [ "$PANEL_MANAGED_SSL" = "true" ]; then
        log INFO "Using control panel managed SSL certificates"
        echo -e "${CYAN}Using SSL certificates managed by control panel${RESET}"
        echo -e "${GREEN}${BOLD}✓${RESET} Control panel SSL configuration will be used"
        return 0
    fi
    
    # Handle Let's Encrypt certificates
    if [ "$CERT_PROVIDER" = "letsencrypt" ]; then
        log INFO "Obtaining Let's Encrypt certificates..."
        echo -e "${CYAN}Obtaining Let's Encrypt certificates for ${BOLD}$DOMAIN${RESET}..."
        
        # Check if certificate already exists
        if [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
            log INFO "Certificate for $DOMAIN already exists"
            echo -e "${GREEN}${BOLD}✓${RESET} Certificate for $DOMAIN already exists"
            
            if confirm "Do you want to renew the existing certificate?"; then
                log INFO "Renewing certificate for $DOMAIN"
                echo -e "${YELLOW}Renewing certificate for $DOMAIN...${RESET}"
                certbot renew --cert-name "$DOMAIN"
                log INFO "Certificate renewed"
                echo -e "${GREEN}${BOLD}✓${RESET} Certificate renewed successfully"
            fi
            
            return 0
        fi
        
        if [ "$SSL_TYPE" = "PROXY" ] && [ "$NGINX_INSTALLED" = "true" ]; then
            # Use Nginx plugin for Certbot
            CERTBOT_COMMAND="certbot --nginx"
            echo -e "${YELLOW}Using Nginx plugin for Certbot${RESET}"
        else
            # Use standalone mode
            CERTBOT_COMMAND="certbot certonly --standalone"
            echo -e "${YELLOW}Using standalone mode for Certbot${RESET}"
            
            # Check if port 80 is in use
            if command -v netstat >/dev/null 2>&1 && netstat -tuln | grep -q ":80 "; then
                log WARNING "Port 80 is already in use. This may cause problems for the HTTP challenge"
                echo -e "${YELLOW}${BOLD}⚠ Warning:${RESET} Port 80 is already in use"
                echo -e "${YELLOW}This may cause problems for the HTTP challenge. Consider temporarily stopping the service using port 80.${RESET}"
                
                if confirm "Do you want to continue anyway?"; then
                    log INFO "Continuing despite port 80 being in use"
                else
                    log ERROR "Certificate acquisition cancelled by user due to port 80 being in use"
                    echo -e "${RED}Certificate acquisition cancelled by user.${RESET}"
                    exit 1
                fi
            fi
        fi
        
        # Add domains
        CERTBOT_COMMAND="$CERTBOT_COMMAND -d $DOMAIN"
        echo -e "${CYAN}Adding domain: $DOMAIN${RESET}"
        
        # Add wildcard domain if specified
        if [ "$USE_WILDCARD" = "true" ] && [ -n "$WILDCARD_DOMAIN" ]; then
            if [ "$CERTBOT_COMMAND" = "certbot certonly --standalone" ]; then
                log WARNING "Wildcard certificates require DNS validation, switching to manual mode"
                echo -e "${YELLOW}${BOLD}⚠ Warning:${RESET} Wildcard certificates require DNS validation"
                CERTBOT_COMMAND="certbot certonly --manual --preferred-challenges dns"
                echo -e "${YELLOW}Switched to manual DNS challenge mode${RESET}"
                echo -e "${YELLOW}You'll need to add a TXT record to your DNS settings when prompted${RESET}"
            fi
            
            CERTBOT_COMMAND="$CERTBOT_COMMAND -d $WILDCARD_DOMAIN"
            echo -e "${CYAN}Adding wildcard domain: $WILDCARD_DOMAIN${RESET}"
        fi
        
        # Add email and flags
        CERTBOT_COMMAND="$CERTBOT_COMMAND --email $CERT_EMAIL --agree-tos"
        
        if [ "$USE_WILDCARD" = "true" ] && [ -n "$WILDCARD_DOMAIN" ]; then
            # For wildcard, we need interactive mode
            echo -e "${YELLOW}${BOLD}DNS Challenge Instructions:${RESET}"
            echo -e "${CYAN}You will be asked to add a TXT record to your DNS settings.${RESET}"
            echo -e "${CYAN}Follow the instructions provided by Certbot and press Enter only after you've added the record.${RESET}"
            echo -e "${CYAN}It may take some time for DNS changes to propagate (up to 24 hours for some providers).${RESET}"
            echo
            
            # Ask for confirmation before proceeding
            if confirm "Ready to proceed with the DNS challenge?"; then
                log INFO "Proceeding with DNS challenge for wildcard certificate"
            else
                log ERROR "Certificate acquisition cancelled by user"
                echo -e "${RED}Certificate acquisition cancelled by user.${RESET}"
                exit 1
            fi
        else
            # For non-wildcard, we can use non-interactive mode
            CERTBOT_COMMAND="$CERTBOT_COMMAND --non-interactive"
        fi
        
        # Execute certbot command
        log INFO "Running: $CERTBOT_COMMAND"
        echo -e "${YELLOW}Executing: $CERTBOT_COMMAND${RESET}"
        
        if ! eval "$CERTBOT_COMMAND"; then
            log ERROR "Failed to obtain Let's Encrypt certificates"
            echo -e "${BG_RED}${WHITE}${BOLD} ERROR ${RESET} Failed to obtain Let's Encrypt certificates"
            echo -e "${RED}Check the output above for more details on the failure.${RESET}"
            
            if [ "$USE_WILDCARD" = "true" ] && [ -n "$WILDCARD_DOMAIN" ]; then
                echo -e "${YELLOW}For wildcard certificates, ensure:${RESET}"
                echo -e "${YELLOW}1. You've added the TXT record correctly${RESET}"
                echo -e "${YELLOW}2. You've waited for DNS propagation${RESET}"
                echo -e "${YELLOW}3. Your DNS provider supports the required records${RESET}"
            else
                echo -e "${YELLOW}Common issues:${RESET}"
                echo -e "${YELLOW}1. Port 80 is already in use${RESET}"
                echo -e "${YELLOW}2. Domain does not point to this server${RESET}"
                echo -e "${YELLOW}3. Firewall blocking required ports${RESET}"
            fi
            
            exit 1
        fi
        
        # Set up automatic renewal if requested
        if [ "$CERT_AUTO_RENEW" = "true" ]; then
            log INFO "Setting up automatic certificate renewal..."
            echo -e "${CYAN}Setting up automatic certificate renewal...${RESET}"
            
            # Check if renewal cron job already exists
            if ! crontab -l 2>/dev/null | grep -q "certbot renew"; then
                (crontab -l 2>/dev/null || true; echo "0 3 * * * certbot renew --quiet") | crontab -
                log INFO "Automatic renewal set up with cron"
                echo -e "${GREEN}${BOLD}✓${RESET} Automatic renewal set up with cron (daily at 3 AM)"
            else
                log INFO "Automatic renewal already configured"
                echo -e "${GREEN}${BOLD}✓${RESET} Automatic renewal already configured"
            fi
        else
            log INFO "Automatic renewal not requested"
            echo -e "${YELLOW}Note: Automatic renewal not enabled. Certificates will expire in 90 days.${RESET}"
            echo -e "${YELLOW}To manually renew, run: ${DIM}certbot renew${RESET}"
        fi
        
        log INFO "Let's Encrypt certificates obtained successfully"
        echo -e "${GREEN}${BOLD}✓${RESET} Let's Encrypt certificates obtained successfully"
    elif [ "$CERT_PROVIDER" = "manual" ]; then
        # Validate manual certificate paths
        if [ -z "$SSL_CERT_PATH" ] || [ -z "$SSL_KEY_PATH" ]; then
            log ERROR "Manual certificate paths not specified"
            echo -e "${BG_RED}${WHITE}${BOLD} ERROR ${RESET} Manual certificate paths not specified"
            echo -e "${RED}Please set SSL_CERT_PATH and SSL_KEY_PATH in $SSL_CONFIG_FILE${RESET}"
            exit 1
        fi
        
        if [ ! -f "$SSL_CERT_PATH" ] || [ ! -f "$SSL_KEY_PATH" ]; then
            log ERROR "Specified certificate files not found"
            echo -e "${BG_RED}${WHITE}${BOLD} ERROR ${RESET} Certificate files not found:"
            echo -e "${RED}Certificate: $SSL_CERT_PATH ($([ -f "$SSL_CERT_PATH" ] && echo "Found" || echo "Not found"))${RESET}"
            echo -e "${RED}Key: $SSL_KEY_PATH ($([ -f "$SSL_KEY_PATH" ] && echo "Found" || echo "Not found"))${RESET}"
            exit 1
        fi
        
        log INFO "Using manually provided certificates"
        echo -e "${GREEN}${BOLD}✓${RESET} Using manually provided certificates:"
        echo -e "${GREEN}Certificate: $SSL_CERT_PATH${RESET}"
        echo -e "${GREEN}Key: $SSL_KEY_PATH${RESET}"
    else
        log ERROR "Unsupported certificate provider: $CERT_PROVIDER"
        echo -e "${BG_RED}${WHITE}${BOLD} ERROR ${RESET} Unsupported certificate provider: $CERT_PROVIDER"
        echo -e "${RED}Supported providers: letsencrypt, manual${RESET}"
        exit 1
    fi
}

# Configure Nginx as a reverse proxy for Odoo
configure_nginx() {
    if [ "$SSL_TYPE" != "PROXY" ]; then
        log INFO "Skipping Nginx configuration as SSL_TYPE is not PROXY"
        return 0
    fi
    
    show_progress "Configuring Nginx Reverse Proxy"
    
    log INFO "Configuring Nginx as reverse proxy for Odoo..."
    echo -e "${CYAN}Configuring Nginx as reverse proxy for Odoo...${RESET}"
    
    # Create Nginx configuration directory if it doesn't exist
    mkdir -p "$NGINX_CONF_PATH"
    echo -e "${YELLOW}Using Nginx configuration directory: $NGINX_CONF_PATH${RESET}"
    
    # Determine certificate paths
    local cert_path="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
    local key_path="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
    
    if [ "$CERT_PROVIDER" = "manual" ]; then
        cert_path="$SSL_CERT_PATH"
        key_path="$SSL_KEY_PATH"
    fi
    
    echo -e "${YELLOW}Using certificate: $cert_path${RESET}"
    echo -e "${YELLOW}Using key: $key_path${RESET}"
    
    # Create Nginx configuration
    log INFO "Creating Nginx configuration at $NGINX_CONF_PATH/odoo.conf"
    echo -e "${CYAN}Creating Nginx configuration file...${RESET}"
    
    cat > "$NGINX_CONF_PATH/odoo.conf" <<EOF
# Odoo Nginx configuration
# Generated by ssl-setup.sh on $(date)

upstream odoo {
    server 127.0.0.1:8069 weight=1 fail_timeout=0;
}

upstream odoo-longpolling {
    server 127.0.0.1:8072 weight=1 fail_timeout=0;
}

server {
    listen 80;
    server_name $DOMAIN;
    
    # Redirect HTTP to HTTPS
    location / {
EOF
    
    if [ "$REDIRECT_HTTP_TO_HTTPS" = "true" ]; then
        cat >> "$NGINX_CONF_PATH/odoo.conf" <<EOF
        # HTTP to HTTPS redirection
        return 301 https://\$host\$request_uri;
EOF
        log INFO "Enabled HTTP to HTTPS redirection"
        echo -e "${GREEN}${BOLD}✓${RESET} Enabled HTTP to HTTPS redirection"
    else
        cat >> "$NGINX_CONF_PATH/odoo.conf" <<EOF
        # No HTTP to HTTPS redirection (proxy pass only)
        proxy_pass http://odoo;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
EOF
        log INFO "HTTP to HTTPS redirection disabled (proxy pass only)"
        echo -e "${YELLOW}HTTP to HTTPS redirection disabled (proxy pass only)${RESET}"
    fi
    
    cat >> "$NGINX_CONF_PATH/odoo.conf" <<EOF
    }
}

server {
    listen $NGINX_SSL_PORT ssl http2;
    server_name $DOMAIN;
    
    # SSL configuration
    ssl_certificate $cert_path;
    ssl_certificate_key $key_path;
    ssl_protocols $SSL_PROTOCOLS;
    ssl_ciphers $SSL_CIPHERS;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
EOF
    
    # Add HSTS if enabled
    if [ "$HSTS_ENABLED" = "true" ]; then
        cat >> "$NGINX_CONF_PATH/odoo.conf" <<EOF
    # HSTS configuration
    add_header Strict-Transport-Security "max-age=$HSTS_MAX_AGE; includeSubDomains" always;
EOF
        log INFO "Enabled HSTS with max-age=$HSTS_MAX_AGE"
        echo -e "${GREEN}${BOLD}✓${RESET} Enabled HSTS (HTTP Strict Transport Security)"
    fi
    
    cat >> "$NGINX_CONF_PATH/odoo.conf" <<EOF
    # Security headers
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Frame-Options SAMEORIGIN;
    
    # Proxy settings
    proxy_read_timeout 720s;
    proxy_connect_timeout 720s;
    proxy_send_timeout 720s;
    
    # Increase proxy buffer size
    proxy_buffers 16 64k;
    proxy_buffer_size 128k;
    
    # General proxy settings
    proxy_http_version 1.1;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Real-IP \$remote_addr;
    
    # WebSocket support
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    
    # Main Odoo proxy
    location / {
        proxy_pass http://odoo;
    }
    
    # Longpolling
    location /longpolling {
        proxy_pass http://odoo-longpolling;
    }
    
    # Static files
    location ~* /web/static/ {
        proxy_pass http://odoo;
        proxy_cache_valid 200 90m;
        proxy_buffering on;
        expires 864000;
    }
    
    # Gzip
    gzip on;
    gzip_min_length 1000;
    gzip_proxied expired no-cache no-store private auth;
    gzip_types text/plain text/xml text/css text/javascript application/javascript application/json;
    gzip_disable "MSIE [1-6]\.";
}
EOF
    
    log INFO "Nginx configuration created at $NGINX_CONF_PATH/odoo.conf"
    echo -e "${GREEN}${BOLD}✓${RESET} Nginx configuration created"
    
    # Test and reload Nginx configuration
    log INFO "Testing Nginx configuration..."
    echo -e "${YELLOW}Testing Nginx configuration...${RESET}"
    
    if ! nginx -t; then
        log ERROR "Nginx configuration test failed"
        echo -e "${BG_RED}${WHITE}${BOLD} ERROR ${RESET} Nginx configuration test failed"
        echo -e "${RED}Check the output above for configuration errors.${RESET}"
        
        if confirm "Do you want to continue anyway? (Not recommended)"; then
            log WARNING "Continuing despite Nginx configuration test failure"
            echo -e "${YELLOW}Continuing despite configuration test failure...${RESET}"
        else
            log ERROR "SSL setup cancelled due to Nginx configuration test failure"
            echo -e "${RED}SSL setup cancelled.${RESET}"
            exit 1
        fi
    else
        echo -e "${GREEN}${BOLD}✓${RESET} Nginx configuration test passed"
    fi
    
    log INFO "Reloading Nginx..."
    echo -e "${YELLOW}Reloading Nginx service...${RESET}"
    
    if ! systemctl reload nginx; then
        log ERROR "Failed to reload Nginx"
        echo -e "${BG_RED}${WHITE}${BOLD} ERROR ${RESET} Failed to reload Nginx"
        
        if confirm "Do you want to try restarting Nginx instead?"; then
            log INFO "Attempting to restart Nginx..."
            echo -e "${YELLOW}Attempting to restart Nginx...${RESET}"
            
            if ! systemctl restart nginx; then
                log ERROR "Failed to restart Nginx"
                echo -e "${BG_RED}${WHITE}${BOLD} ERROR ${RESET} Failed to restart Nginx"
                echo -e "${RED}Nginx configuration may be invalid or there might be other issues.${RESET}"
                exit 1
            else
                log INFO "Nginx restarted successfully"
                echo -e "${GREEN}${BOLD}✓${RESET} Nginx restarted successfully"
            fi
        else
            log ERROR "SSL setup cancelled due to Nginx reload failure"
            echo -e "${RED}SSL setup cancelled.${RESET}"
            exit 1
        fi
    else
        log INFO "Nginx reloaded successfully"
        echo -e "${GREEN}${BOLD}✓${RESET} Nginx reloaded successfully"
    fi
    
    log INFO "Nginx configured successfully"
    echo -e "${GREEN}${BOLD}✓${RESET} Nginx reverse proxy configured successfully"
}

# Configure Odoo for direct SSL (no proxy)
configure_direct_ssl() {
    if [ "$SSL_TYPE" != "DIRECT" ]; then
        log INFO "Skipping direct SSL configuration as SSL_TYPE is not DIRECT"
        return 0
    fi
    
    show_progress "Configuring Direct SSL in Odoo"
    
    log INFO "Configuring Odoo for direct SSL..."
    echo -e "${CYAN}Configuring Odoo for direct SSL handling...${RESET}"
    
    # Determine certificate paths
    local cert_path="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
    local key_path="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
    
    if [ "$CERT_PROVIDER" = "manual" ]; then
        cert_path="$SSL_CERT_PATH"
        key_path="$SSL_KEY_PATH"
    fi
    
    echo -e "${YELLOW}Using certificate: $cert_path${RESET}"
    echo -e "${YELLOW}Using key: $key_path${RESET}"
    
    # Check if certificate files are readable by Odoo
    if [ ! -r "$cert_path" ] || [ ! -r "$key_path" ]; then
        log WARNING "Certificate files may not be readable by Odoo"
        echo -e "${YELLOW}${BOLD}⚠ Warning:${RESET} Certificate files may not be readable by Odoo"
        echo -e "${YELLOW}You may need to adjust permissions or create symbolic links${RESET}"
        
        if confirm "Would you like to attempt to fix permissions?"; then
            log INFO "Attempting to fix certificate permissions..."
            echo -e "${YELLOW}Attempting to fix certificate permissions...${RESET}"
            
            # Create a directory for certificates in Odoo config directory
            mkdir -p "$SCRIPT_DIR/config/certs"
            
            # Copy certificates with proper permissions
            cp "$cert_path" "$SCRIPT_DIR/config/certs/fullchain.pem"
            cp "$key_path" "$SCRIPT_DIR/config/certs/privkey.pem"
            chmod 644 "$SCRIPT_DIR/config/certs/fullchain.pem"
            chmod 600 "$SCRIPT_DIR/config/certs/privkey.pem"
            
            # Update paths
            cert_path="$SCRIPT_DIR/config/certs/fullchain.pem"
            key_path="$SCRIPT_DIR/config/certs/privkey.pem"
            
            log INFO "Copied certificates to $SCRIPT_DIR/config/certs/ with correct permissions"
            echo -e "${GREEN}${BOLD}✓${RESET} Copied certificates with correct permissions"
        fi
    fi
    
    # Update Odoo configuration file
    log INFO "Updating Odoo configuration for direct SSL..."
    echo -e "${CYAN}Updating Odoo configuration file for direct SSL...${RESET}"
    
    # Check if we should use the direct-ssl-config.conf template
    if [ -f "$SCRIPT_DIR/direct-ssl-config.conf" ]; then
        log INFO "Using direct-ssl-config.conf template"
        echo -e "${YELLOW}Using direct-ssl-config.conf template...${RESET}"
        
        # Replace certificate paths in the template
        local temp_config=$(mktemp)
        cat "$SCRIPT_DIR/direct-ssl-config.conf" > "$temp_config"
        
        # Update paths
        sed -i "s|ssl_certificate = .*|ssl_certificate = $cert_path|" "$temp_config"
        sed -i "s|ssl_certificate_key = .*|ssl_certificate_key = $key_path|" "$temp_config"
        
        # Append to odoo.conf
        log INFO "Appending direct SSL configuration to Odoo config"
        echo -e "\n# Direct SSL Configuration (added by ssl-setup.sh)" >> "$ODOO_CONFIG_FILE"
        cat "$temp_config" | grep -v "^#" >> "$ODOO_CONFIG_FILE"
        
        # Clean up
        rm -f "$temp_config"
        
        log INFO "Direct SSL configuration added to Odoo config using template"
        echo -e "${GREEN}${BOLD}✓${RESET} Direct SSL configuration added using template"
    else
        # Check if direct SSL config is already in the file
        if grep -q "ssl = True" "$ODOO_CONFIG_FILE"; then
            log INFO "Direct SSL configuration already exists, updating it"
            echo -e "${YELLOW}Existing SSL configuration found, updating...${RESET}"
            
            # Update existing configuration
            sed -i "s|ssl_certificate = .*|ssl_certificate = $cert_path|" "$ODOO_CONFIG_FILE"
            sed -i "s|ssl_certificate_key = .*|ssl_certificate_key = $key_path|" "$ODOO_CONFIG_FILE"
            sed -i "s|ssl_port = .*|ssl_port = $NGINX_SSL_PORT|" "$ODOO_CONFIG_FILE"
        else
            # Add direct SSL configuration
            log INFO "Adding direct SSL configuration to Odoo config"
            echo -e "${YELLOW}Adding SSL configuration to Odoo config file...${RESET}"
            
            cat >> "$ODOO_CONFIG_FILE" <<EOF

# SSL Configuration
# Added by ssl-setup.sh on $(date)
ssl = True
ssl_certificate = $cert_path
ssl_certificate_key = $key_path
ssl_port = $NGINX_SSL_PORT
ssl_min_version = TLSv1_2
EOF
        fi
        
        log INFO "Direct SSL configuration added to Odoo config"
        echo -e "${GREEN}${BOLD}✓${RESET} Direct SSL configuration added to Odoo config"
    fi
}

# Update Odoo configuration for SSL
update_odoo_config() {
    show_progress "Updating Odoo Configuration"
    
    log INFO "Updating Odoo configuration for SSL..."
    echo -e "${CYAN}Updating Odoo configuration for SSL...${RESET}"
    
    # Ensure proxy_mode is enabled for PROXY SSL type
    if [ "$SSL_TYPE" = "PROXY" ]; then
        if ! grep -q "proxy_mode\s*=\s*True" "$ODOO_CONFIG_FILE"; then
            log INFO "Adding proxy_mode = True to Odoo configuration"
            echo -e "${YELLOW}Adding proxy_mode = True to Odoo configuration...${RESET}"
            echo "proxy_mode = True" >> "$ODOO_CONFIG_FILE"
        else
            log INFO "proxy_mode is already enabled"
            echo -e "${GREEN}${BOLD}✓${RESET} proxy_mode is already enabled"
        fi
    fi
    
    # Set correct report.url parameter based on domain
    local report_url="https://$DOMAIN"
    
    if grep -q "report.url" "$ODOO_CONFIG_FILE"; then
        # Update existing report.url
        log INFO "Updating existing report.url parameter"
        echo -e "${YELLOW}Updating existing report.url parameter...${RESET}"
        sed -i "s|^report.url.*|report.url = $report_url|" "$ODOO_CONFIG_FILE"
    else
        # Add report.url
        log INFO "Adding report.url parameter"
        echo -e "${YELLOW}Adding report.url parameter...${RESET}"
        echo "report.url = $report_url" >> "$ODOO_CONFIG_FILE"
    fi
    
    log INFO "Odoo configuration updated for SSL"
    echo -e "${GREEN}${BOLD}✓${RESET} Odoo configuration updated for SSL"
}

# Restart Odoo service to apply changes
restart_odoo() {
    show_progress "Restarting Odoo Service"
    
    log INFO "Restarting Odoo to apply configuration changes..."
    echo -e "${CYAN}Restarting Odoo to apply configuration changes...${RESET}"
    
    cd "$SCRIPT_DIR"
    
    # Using docker-compose to restart the Odoo service
    if [ -f "docker-compose.yml" ]; then
        if command -v docker-compose >/dev/null 2>&1; then
            echo -e "${YELLOW}Using docker-compose to restart Odoo...${RESET}"
            docker-compose restart web
        elif command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
            echo -e "${YELLOW}Using docker compose plugin to restart Odoo...${RESET}"
            docker compose restart web
        else
            log ERROR "Docker Compose not available"
            echo -e "${BG_RED}${WHITE}${BOLD} ERROR ${RESET} Docker Compose not available"
            echo -e "${RED}Cannot restart Odoo containers without Docker Compose${RESET}"
            exit 1
        fi
    else
        log ERROR "docker-compose.yml not found"
        echo -e "${BG_RED}${WHITE}${BOLD} ERROR ${RESET} docker-compose.yml not found"
        echo -e "${RED}Cannot restart Odoo without docker-compose.yml${RESET}"
        exit 1
    fi
    
    log INFO "Odoo restarted successfully"
    echo -e "${GREEN}${BOLD}✓${RESET} Odoo restarted successfully"
}

# Verify SSL setup
verify_ssl() {
    show_progress "Verifying SSL Configuration"
    
    log INFO "Verifying SSL configuration..."
    echo -e "${CYAN}Verifying SSL configuration...${RESET}"
    
    local url="https://$DOMAIN"
    local timeout=10
    
    log INFO "Testing connection to $url with $timeout second timeout..."
    echo -e "${YELLOW}Testing connection to $url (timeout: ${timeout}s)...${RESET}"
    
    # Wait a moment for everything to restart
    echo -e "${YELLOW}Waiting for services to initialize...${RESET}"
    sleep 5
    
    # Try to connect to the HTTPS URL
    echo -ne "${YELLOW}Connecting to $url...${RESET}"
    
    if command -v curl >/dev/null 2>&1; then
        local status=$(curl -s -k -m "$timeout" -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "failed")
        
        if [ "$status" = "failed" ]; then
            echo -e "\r${RED}${BOLD}⚠ Failed${RESET} to connect to $url                   "
            log WARNING "SSL verification failed: Could not connect to $url"
        elif echo "$status" | grep -q "200\|302\|301"; then
            echo -e "\r${GREEN}${BOLD}✓ Success${RESET} - Connected to $url (HTTP $status)                  "
            log INFO "SSL verification successful: $url is accessible (HTTP $status)"
            return 0
        else
            echo -e "\r${YELLOW}${BOLD}⚠ Warning${RESET} - Connected to $url but received HTTP $status          "
            log WARNING "SSL verification partial: Connected to $url but received HTTP $status"
        fi
    elif command -v wget >/dev/null 2>&1; then
        if wget -q --no-check-certificate -T "$timeout" --spider "$url" 2>/dev/null; then
            echo -e "\r${GREEN}${BOLD}✓ Success${RESET} - Connected to $url                  "
            log INFO "SSL verification successful: $url is accessible"
            return 0
        else
            echo -e "\r${RED}${BOLD}⚠ Failed${RESET} to connect to $url                   "
            log WARNING "SSL verification failed: Could not connect to $url"
        fi
    else
        echo -e "\r${YELLOW}${BOLD}⚠ Warning${RESET} - Could not verify: Neither curl nor wget available         "
        log WARNING "Could not verify SSL: Neither curl nor wget available"
    fi
    
    echo -e "\n${YELLOW}${BOLD}Verification Issues:${RESET}"
    echo -e "${YELLOW}1. DNS may not be configured correctly. Make sure $DOMAIN points to this server.${RESET}"
    echo -e "${YELLOW}2. Firewall may be blocking port 443. Check your firewall settings.${RESET}"
    echo -e "${YELLOW}3. Nginx/Odoo may not be configured correctly. Check logs for errors.${RESET}"
    echo -e "${YELLOW}4. Certificate may not be properly installed. Check paths and permissions.${RESET}"
    
    if confirm "Would you like to continue anyway?"; then
        log WARNING "Continuing despite SSL verification failure"
        echo -e "${YELLOW}Continuing despite verification failure. You may need to troubleshoot manually.${RESET}"
        return 0
    else
        log ERROR "SSL setup cancelled due to verification failure"
        echo -e "${RED}SSL setup cancelled due to verification failure.${RESET}"
        exit 1
    fi
}

# Show completion message
show_completion() {
    echo -e "\n${BG_GREEN}${WHITE}${BOLD} SSL SETUP COMPLETE ${RESET}\n"
    echo -e "${GREEN}${BOLD}SSL/HTTPS has been configured successfully!${RESET}"
    echo -e "${CYAN}${BOLD}Your Odoo instance should now be accessible at:${RESET}"
    echo -e "  ${BOLD}HTTPS:${RESET} https://$DOMAIN"
    
    echo -e "\n${CYAN}${BOLD}SSL Configuration Type:${RESET} $SSL_TYPE"
    echo -e "${CYAN}${BOLD}Certificate Provider:${RESET} $CERT_PROVIDER"
    
    if [ "$CERT_PROVIDER" = "letsencrypt" ]; then
        echo -e "${CYAN}${BOLD}Certificate Renewal:${RESET} $([ "$CERT_AUTO_RENEW" = "true" ] && echo "Automatic" || echo "Manual")"
        echo -e "${CYAN}${BOLD}Certificate Location:${RESET} /etc/letsencrypt/live/$DOMAIN/"
    elif [ "$CERT_PROVIDER" = "manual" ]; then
        echo -e "${CYAN}${BOLD}Certificate:${RESET} $SSL_CERT_PATH"
        echo -e "${CYAN}${BOLD}Key:${RESET} $SSL_KEY_PATH"
    fi
    
    echo -e "\n${CYAN}${BOLD}Configuration Files:${RESET}"
    echo -e "  ${YELLOW}SSL Config:${RESET}     ${DIM}$SSL_CONFIG_FILE${RESET}"
    echo -e "  ${YELLOW}Odoo Config:${RESET}    ${DIM}$ODOO_CONFIG_FILE${RESET}"
    
    if [ "$SSL_TYPE" = "PROXY" ]; then
        echo -e "  ${YELLOW}Nginx Config:${RESET}   ${DIM}$NGINX_CONF_PATH/odoo.conf${RESET}"
    fi
    
    echo -e "  ${YELLOW}Log File:${RESET}       ${DIM}$LOG_FILE${RESET}"
    
    echo -e "\n${CYAN}${BOLD}Useful Commands:${RESET}"
    if [ "$CERT_PROVIDER" = "letsencrypt" ]; then
        echo -e "  ${YELLOW}Renew Certificate:${RESET} ${DIM}certbot renew${RESET}"
        echo -e "  ${YELLOW}Certificate Info:${RESET}  ${DIM}certbot certificates${RESET}"
    fi
    
    if [ "$SSL_TYPE" = "PROXY" ]; then
        echo -e "  ${YELLOW}Nginx Status:${RESET}     ${DIM}systemctl status nginx${RESET}"
        echo -e "  ${YELLOW}Nginx Logs:${RESET}       ${DIM}tail -f /var/log/nginx/error.log${RESET}"
    fi
    
    echo -e "  ${YELLOW}Restart Odoo:${RESET}     ${DIM}cd $SCRIPT_DIR && docker-compose restart web${RESET}"
    echo -e "  ${YELLOW}Odoo Logs:${RESET}        ${DIM}docker logs -f $(docker ps | grep odoo17 | awk '{print $1}')${RESET}"
    
    echo -e "\n${GREEN}${BOLD}Enjoy your secure Odoo installation!${RESET}\n"
}

# Main function
main() {
    # Display banner
    show_banner
    
    # Ensure log directory exists
    mkdir -p "$(dirname "$LOG_FILE")"
    
    log INFO "Starting Odoo 17 SSL configuration..."
    
    # Load SSL configuration
    load_ssl_config
    
    # Analyze environment
    analyze_environment
    
    # Show SSL configuration summary and ask for confirmation
    show_ssl_summary
    
    # Detect environment
    detect_environment
    
    # Install dependencies
    install_dependencies
    
    # Get SSL certificates
    get_certificates
    
    # Configure based on SSL type
    if [ "$SSL_TYPE" = "PROXY" ]; then
        configure_nginx
    elif [ "$SSL_TYPE" = "DIRECT" ]; then
        configure_direct_ssl
    else
        log ERROR "Unsupported SSL_TYPE: $SSL_TYPE (must be PROXY or DIRECT)"
        echo -e "${BG_RED}${WHITE}${BOLD} ERROR ${RESET} Unsupported SSL_TYPE: $SSL_TYPE"
        echo -e "${RED}SSL_TYPE must be either PROXY or DIRECT${RESET}"
        exit 1
    fi
    
    # Update Odoo configuration
    update_odoo_config
    
    # Restart Odoo
    restart_odoo
    
    # Verify setup
    verify_ssl
    
    log INFO "SSL configuration completed successfully"
    
    # Show completion message
    show_completion
}

# Run main function
main 