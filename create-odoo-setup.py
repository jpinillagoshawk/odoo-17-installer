#!/usr/bin/env python3
"""
Odoo 17 Parameterization Tool

This script customizes the Odoo 17 setup by replacing template placeholders with 
client-specific values defined in a configuration file.

Usage:
    python3 create-odoo-setup.py <config_file>

Configuration file format:
    client_name=acme
    client_password=acme2025
    user=ubuntu
    odoo_port=8069
    db_port=5432
    db_user=odoo
    odoo_db_name=acme
    path_to_install=/opt
"""

import os
import sys
import shutil
import re
import socket
from pathlib import Path

# Files to be processed
FILES_TO_PROCESS = [
    "docker-compose.yml",
    "install.sh",
    "backup.sh",
    "staging.sh",
    "git_panel.sh",
    "fix-permissions.sh",
    "config/odoo.conf",
    "README.md"
]

# Default configuration values
DEFAULT_CONFIG = {
    'odoo_port': '8069',
    'gevent_port': '8072',
    'db_port': '5432',
    'db_user': 'odoo',
    'path_to_install': '',  # Will use current directory if blank
    'user': ''  # Will be auto-detected if blank
}

def print_usage():
    """Print usage message"""
    print("Usage: python3 create-odoo-setup.py <config_file>")
    print("Example: python3 create-odoo-setup.py odoo-17-setup.conf")


def get_public_ip():
    """Get the public IP of the machine"""
    services = [
        "https://api.ipify.org",
        "https://ipinfo.io/ip",
        "https://ifconfig.me/ip",
        "https://icanhazip.com"
    ]
    
    for service in services:
        try:
            import urllib.request
            response = urllib.request.urlopen(service, timeout=5)
            ip = response.read().decode('utf-8').strip()
            if ip and len(ip) <= 15:  # Basic validation for IPv4
                return ip
        except Exception as e:
            continue
    
    # If all services fail
    print("Warning: Could not determine public IP. Please specify it manually in the config file.")
    return "localhost"

def get_user_input(field_name, validation_func=None, error_message=None):
    """Get and validate user input for a field"""
    while True:
        value = input(f"Enter {field_name}: ").strip()
        if validation_func and not validation_func(value):
            print(error_message)
        else:
            return value

def validate_client_name(name):
    """Validate that client name is alphanumeric"""
    return name.isalnum()

def load_config(config_file):
    """Load configuration from file"""
    if not os.path.exists(config_file):
        print(f"Error: Configuration file '{config_file}' not found.")
        sys.exit(1)
    
    config = dict(DEFAULT_CONFIG)  # Start with default values
    
    # Read config file
    with open(config_file, 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
                
            if '=' in line:
                key, value = line.split('=', 1)
                key = key.strip()
                value = value.strip()
                
                # Only use non-empty values
                if value:
                    config[key] = value
    
    # Check for required fields and prompt if missing
    required_fields = ['client_name', 'client_password']
    missing_fields = [field for field in required_fields if not config.get(field)]
    
    if missing_fields:
        print(f"The following required fields are missing in config file: {', '.join(missing_fields)}")
        
        if 'client_name' in missing_fields:
            config['client_name'] = get_user_input(
                "client_name (alphanumeric characters only)",
                validate_client_name,
                "Error: client_name must contain only alphanumeric characters"
            ).lower()
        elif 'client_name' in config and not validate_client_name(config['client_name']):
            print("Error: client_name in config file must contain only alphanumeric characters")
            config['client_name'] = get_user_input(
                "client_name (alphanumeric characters only)",
                validate_client_name,
                "Error: client_name must contain only alphanumeric characters"
            ).lower()
        
        if 'client_password' in missing_fields:
            config['client_password'] = get_user_input(
                "client_password"
            )

    # Set container names
    config['odoo_container_name'] = f"odoo17-{config['client_name']}"
    config['db_container_name'] = f"db-{config['client_name']}"
    
    # Get parent directory of the current script location
    current_dir = os.path.dirname(os.path.abspath(__file__))
    parent_dir = os.path.dirname(current_dir)
    
    # Set default values for missing fields
    if not config.get('path_to_install'):
        # Default to parent directory of current directory
        config['path_to_install'] = parent_dir
        print(f"Using default path_to_install: {config['path_to_install']}")
    
    # Set target setup directory
    config['target_setup_dir'] = os.path.join(config['path_to_install'], f"{config['client_name']}-odoo17-setup")
    
    # Set install_dir variable
    config['install_dir'] = os.path.join(config['path_to_install'], f"{config['client_name']}-odoo-17")
    
    # Auto-detect user if not specified
    if not config.get('user'):
        try:
            import getpass
            config['user'] = getpass.getuser()
            print(f"Auto-detected user: {config['user']}")
        except Exception:
            config['user'] = 'root'
            print(f"Could not detect user, using default: {config['user']}")
    
    # Auto-detect IP if not specified
    if not config.get('ip'):
        config['ip'] = get_public_ip()
        print(f"Auto-detected IP address: {config['ip']}")
    
    # Ensure db_user is set (should already be from defaults, but double check)
    if not config.get('db_user'):
        config['db_user'] = DEFAULT_CONFIG['db_user']
        print(f"Using default db_user: {config['db_user']}")
    
    #Ensure odoo_db_name is set
    if not config.get('odoo_db_name'):
        config['odoo_db_name'] = config['client_name']
        print(f"Using default odoo_db_name: {config['odoo_db_name']}")
    
    # Print all configuration values for verification
    print("\nConfiguration values that will be used:")
    for key, value in config.items():
        print(f"  {key} = {value}")
    print()
    
    return config

def copy_template_files(source_dir, target_dir):
    """Copy all template files to the target directory"""
    print(f"Copying template files to {target_dir}...")
    
    # Create the target directory if it doesn't exist
    os.makedirs(target_dir, exist_ok=True)
    
    # Ensure config directory exists in the target
    os.makedirs(os.path.join(target_dir, 'config'), exist_ok=True)
    
    # Copy each file in FILES_TO_PROCESS
    for file_name in FILES_TO_PROCESS:
        source_path = os.path.join(source_dir, file_name)
        target_path = os.path.join(target_dir, file_name)
        
        # Create target subdirectories if needed
        os.makedirs(os.path.dirname(target_path), exist_ok=True)
        
        if os.path.exists(source_path):
            shutil.copy2(source_path, target_path)
            print(f"  Copied: {file_name}")
        else:
            print(f"  Warning: Source file not found: {source_path}")
    
    # Copy any additional files/directories that might be useful
    for item in os.listdir(source_dir):
        if item not in ['__pycache__', '.git', '.github', '.vscode', 'backups_original'] and not item.endswith('.pyc'):
            source_item = os.path.join(source_dir, item)
            target_item = os.path.join(target_dir, item)
            
            if os.path.isfile(source_item) and item not in [os.path.basename(__file__)]:
                shutil.copy2(source_item, target_item)
                print(f"  Copied additional file: {item}")
            elif os.path.isdir(source_item) and item not in ['config']:
                shutil.copytree(source_item, target_item, dirs_exist_ok=True)
                print(f"  Copied additional directory: {item}")
    
    print("Template files copied successfully.")
    return True

def modify_file(file_path, config):
    """Replace all template placeholders with actual values"""
    if not os.path.exists(file_path):
        print(f"Warning: File does not exist: {file_path}")
        return False
        
    # Read file content
    with open(file_path, 'r', encoding='utf-8', errors='ignore') as file:
        content = file.read()
    
    # Apply replacements
    content = content.replace('{client_name}', config['client_name'])
    content = content.replace('{client_password}', config['client_password'])
    content = content.replace('{odoo_port}', config['odoo_port'])
    content = content.replace('{gevent_port}', config['gevent_port'])
    content = content.replace('{db_port}', config['db_port'])
    content = content.replace('{db_user}', config['db_user'])
    content = content.replace('{path_to_install}', config['path_to_install'])
    content = content.replace('{odoo_container_name}', config['odoo_container_name'])
    content = content.replace('{db_container_name}', config['db_container_name'])
    content = content.replace('odoo_db_name', config['odoo_db_name'])
    content = content.replace('{install_dir}', config['install_dir'])

    if 'ip' in config:
        content = content.replace('{ip}', config['ip'])
    else:
        content = content.replace('{ip}', 'localhost')
    
    if 'user' in config:
        content = content.replace('{user}', config['user']) 
    else:
        content = content.replace('{user}', 'root')
    
    # List of placeholders to ignore (formatting and color codes)
    ignored_placeholders = {
        # Color codes
        'WHITE', 'RED', 'YELLOW', 'GREEN', 'CYAN', 'MAGENTA', 'BLACK', 'BLUE', 'NC',
        # Background colors
        'BG_RED', 'BG_BLUE', 'BG_GREEN', 'BG_CYAN', 'BG_MAGENTA', 'BG_YELLOW',
        # Text formatting
        'BOLD', 'DIM', 'UNDERLINE', 'RESET',
        # Other shell script variables
        'level_color', 'http_code', 'TIMESTAMP', 'DB_NAME', 'docker_compose_file',
        'odoo_conf_file', 'file_name', 'container_name', 'module_name', 
        'insertions', 'deletions', 'win_archive', 'win_target', 'INSTALL_DIR', 'enterprise_path', 'i'
    }
    
    # Check for any remaining unparsed placeholders
    remaining_placeholders = re.findall(r'\{([a-zA-Z_]+)\}', content)
    remaining_placeholders = [p for p in remaining_placeholders if p not in ignored_placeholders]
    
    if remaining_placeholders:
        print(f"Warning: The following placeholders were not replaced in {file_path}:")
        for placeholder in set(remaining_placeholders):
            print(f"  - {{{placeholder}}}")
    
    # Write modified content back to file
    with open(file_path, 'w', encoding='utf-8') as file:
        file.write(content)
        
    print(f"Modified: {file_path}")
    return True

def create_odoo_conf(config, target_dir):
    """Create and customize the odoo.conf file for Docker deployment only if it doesn't exist"""
    config_dir = os.path.join(target_dir, 'config')
    os.makedirs(config_dir, exist_ok=True)
    
    config_path = os.path.join(config_dir, 'odoo.conf')
    
    # Only create the file if it doesn't exist
    if not os.path.exists(config_path):
        # Create the odoo.conf file
        with open(config_path, 'w', encoding='utf-8') as file:
            file.write("""[options]
admin_passwd = {client_password}
db_host = db
db_port = {db_port}
db_user = {db_user}
db_password = {client_password}
db_name = odoo_db_name
dbfilter = odoo_db_name
database = odoo_db_name
addons_path = /mnt/enterprise,/mnt/extra-addons,/usr/lib/python3/dist-packages/odoo/addons
data_dir = /var/lib/odoo
session_dir = /var/lib/odoo/sessions
logfile = /var/log/odoo/odoo.log
log_level = info
max_cron_threads = 2
workers = 4
limit_memory_hard = 2684354560
limit_memory_soft = 2147483648
limit_request = 8192
limit_time_cpu = 600
limit_time_real = 1200
proxy_mode = True
""")
        print(f"Created Odoo configuration file at {config_path}")
    else:
        print(f"Odoo configuration file already exists at {config_path}, modifying it")
        modify_file(config_path, config)
    
    return True

def create_sample_config(filename):
    """Create a sample configuration file"""
    with open(filename, 'w', encoding='utf-8') as file:
        file.write("""# Odoo 17 Setup Configuration
# Required parameters
client_name=acme
client_password=acme2025

# Optional parameters (leave blank for auto-detection)
user=
ip=
odoo_port=8069
gevent_port=8072
db_port=5432
db_user=odoo
path_to_install=
""")
    print(f"Created sample configuration file: {filename}")
    return filename

def main():
    """Main function"""
    # Common configuration file names to look for
    common_config_files = [
        'odoo-setup.conf',
        'odoo-17-setup.conf',
        'odoo.conf'
    ]
    
    if len(sys.argv) != 2:
        print_usage()
        
        # If no arguments, check for existing config files
        if len(sys.argv) == 1:
            found_config = None
            for config_name in common_config_files:
                if os.path.exists(config_name):
                    found_config = config_name
                    break
            
            if found_config:
                print(f"\nFound existing configuration file: {found_config}")
                print(f"Using this file. To use a different file, specify it as an argument.")
                config_file = found_config
            else:
                config_file = create_sample_config('odoo-setup.conf')
                print("\nA sample configuration file has been created. Edit this file and run the script again.")
                sys.exit(1)
        else:
            sys.exit(1)
    else:
        config_file = sys.argv[1]
    
    config = load_config(config_file)
    
    print(f"Customizing setup for client: {config['client_name']}")
    
    # Get current directory (where this script is located)
    current_dir = os.path.dirname(os.path.abspath(__file__))
    
    # Copy template files to the target setup directory
    target_setup_dir = config['target_setup_dir']
    copy_template_files(current_dir, target_setup_dir)
    
    # Process each file in the target directory
    for file_name in FILES_TO_PROCESS:
        file_path = os.path.join(target_setup_dir, file_name)
        if os.path.exists(file_path):
            modify_file(file_path, config)
        else:
            print(f"Warning: File not found in target directory: {file_path}")
    
    # Create odoo.conf
    create_odoo_conf(config, target_setup_dir)
    
    print("\nParameterization completed successfully!")
    print(f"The setup is now customized for client: {config['client_name']}")
    print("\nNext steps:")
    print("1. Review the modified files to ensure correct parameterization")
    print(f"2. Download or copy the enterprise DEB file (odoo_17.0+e.latest_all.deb) to THIS directory: {config['path_to_install']}")
    print("3. Change to the client-specific setup directory and run install.sh to deploy the Odoo instance:")
    print(f"   cd {target_setup_dir} && chmod +x install.sh && sudo -E ./install.sh")
    print(f"\nOdoo will be installed in: {config['install_dir']}")

if __name__ == "__main__":
    main() 