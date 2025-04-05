# Odoo 17 SSL/HTTPS Implementation Project

## Context and Overview

You are tasked with implementing SSL/HTTPS support for an Odoo 17 Docker-based installation system. The project consists of scripts and configuration files that automate the creation of customized Odoo 17 setups for different clients. Your specific task is to enhance the system with robust SSL/HTTPS support that can handle various server environments.

The current implementation includes:
- A Python script (`create_client_setup.py`) that generates client-specific Odoo installations
- A template folder (`{client_name}-odoo-17-setup`) used to copy using the parameters specified in the config files
- Shell scripts for installation, backup, and staging environment management
- Docker configuration for containerized deployment
- Directory structure templates for Odoo and PostgreSQL

## Implementation Requirements

Implement a comprehensive SSL/HTTPS solution that:

1. Supports both reverse proxy (Nginx) and direct SSL configurations
2. Handles wildcard certificates for staging environments
3. Detects and integrates with control panels (cPanel/Plesk) when present
4. Provides automated Let's Encrypt certificate acquisition and renewal
5. Offers fallback to manual certificate installation
6. Properly configures Odoo to work with SSL (proxy_mode, report.url parameters)
7. Includes proper security headers and optimal SSL parameters

## Implementation Plan

### Phase 1: Configuration and Detection Framework
- Complete the SSL configuration file structure (building on `ssl-config.conf.template`)
- Develop control panel detection mechanisms
- Create Nginx detection and installation script
- Update the main installation script to include SSL setup

### Phase 2: Certificate Management
- Implement Certbot integration for Let's Encrypt certificates
- Support wildcard certificate requests
- Configure automated renewal via cron jobs
- Create secure certificate storage and management

### Phase 3: Reverse Proxy Configuration
- Create Nginx configuration templates for Odoo
- Implement HTTP to HTTPS redirection
- Configure WebSocket support for Odoo long-polling
- Set up virtual hosts for multi-domain support

### Phase 4: Odoo Configuration
- Update Odoo configuration for proper SSL operation
- Set correct proxy parameters and report URLs
- Create validation and testing scripts

## Technical Constraints

- The implementation must work on various Linux distributions
- It must handle both fresh installations and updates to existing deployments
- The solution should be automated with minimal user intervention
- Error handling must be robust with clear error messages
- All security best practices must be followed

## Available Files and Resources

1. `ssl-config.conf.template` - Template for SSL configuration parameters
2. `SSL-README.md` - Documentation for users on SSL configuration
3. `create_client_setup.py` - Main script for client setup generation
4. `{client_name}-odoo-17-setup/` - Template directory structure containing:
   - `install.sh` - Main installation script
   - `docker-compose.yml` - Docker configuration
   - `config/` - Configuration directory
   - Other support files and directories

## Implementation Approach

You should first create a `ssl-setup.sh` script that:
1. Reads parameters from `ssl-config.conf`
2. Detects environment (control panels, existing SSL, etc.)
3. Installs required dependencies (Nginx, Certbot)
4. Configures the selected SSL method (proxy or direct)
5. Obtains certificates (Let's Encrypt or manual)
6. Configures Nginx if using reverse proxy
7. Updates Odoo configuration to work with SSL
8. Sets up automatic renewal

The script should be integrated with the existing `install.sh` script and should be callable separately for post-installation SSL setup.

## Code Style and Standards

- Follow existing shell script style and conventions
- Use meaningful variable names and add comments
- Include error handling and validation for each step
- Create detailed logs of all operations
- Add appropriate permissions and security measures

## Testing Requirements

The implementation should include tests for:
- Certificate acquisition and validation
- Nginx configuration verification
- Odoo accessibility over HTTPS
- WebSocket functionality
- Certificate renewal process

## Deliverables

1. `ssl-setup.sh` - Main SSL setup script
2. Nginx configuration templates
3. Updated installation scripts
4. Comprehensive documentation in README
5. Updated docker-compose configuration

## Function Signatures (Pseudo-code)

```bash
# Main functions to implement

# Detect environment and control panels
detect_environment() {
    # Detect OS, control panels, existing SSL
    # Return environment variables
}

# Install Nginx if needed
install_nginx() {
    # Check if Nginx is installed
    # Install if not present
    # Return success/failure
}

# Configure Nginx for Odoo
configure_nginx() {
    # Create virtual host configuration
    # Set up SSL parameters
    # Configure proxy settings
    # Enable site
}

# Get SSL certificates
get_certificates() {
    # Use Let's Encrypt or manual certs
    # Handle wildcard if needed
    # Set up renewal
}

# Update Odoo configuration
update_odoo_config() {
    # Set proxy_mode
    # Configure report.url
    # Update other SSL-related parameters
}
```

Implement these components systematically, ensuring each part works before moving to the next. Build upon the existing `ssl-config.conf.template` and documentation.
