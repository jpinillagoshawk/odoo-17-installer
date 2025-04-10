#!/usr/bin/env python3
"""
Odoo 17 Client Setup Generator

This script creates a customized Odoo 17 setup for a specific client by:
1. Looking for a template folder named "{client_name}-odoo-17-setup"
2. Creating a new client folder based on the template
3. Replacing all instances of '{client_name}' with the new client name
4. Replacing all instances of '{client_password}' with the new client password
5. Replacing all instances of '{ip}' with the new client IP address
6. Replacing all instances of '{odoo_port}' with the new client Odoo port
7. Replacing all instances of '{db_port}' with the new client database port
8. Replacing all instances of '{db_user}' with the new client database user
9. Customizing installation parameters based on config file

Usage:
    python3 create_client_setup.py <config_file>

Configuration file format (odoo-17-setup.conf):
    client_name=acme
    client_password=acme2025
    user=ubuntu
    ip=195.190.194.108
    odoo_port=8069
    db_port=5432
    db_user=odoo
    path_to_install=/opt
"""

import os
import sys
import shutil
import re
import glob
import socket
import configparser
from pathlib import Path

TEMPLATE_NAME = "{client_name}-odoo-17-setup"
INSTALL_DIR_NAME = "{client_name}-odoo-17"

# Files to be copied and modified
FILES_TO_COPY = [
    "README.md",
    "staging.sh",
    "backup.sh",
    "requirements.txt",
    "install.sh",
    "docker-compose.yml",
    "ssl-setup.sh",
    "direct-ssl-config.conf",
    "git_panel.sh"
]

# Directories to be created if they don't exist in template
DIRS_TO_CREATE = [
    "config",
    "volumes/odoo-data/filestore",
    "volumes/postgres-data",
    "backups/daily",
    "backups/monthly",
    "logs",
    "enterprise",
    "addons",
    "filestore"
]

# Default odoo.conf content
DEFAULT_ODOO_CONF = """[options]
admin_passwd = {password}
db_host = db
db_port = {db_port}
db_user = {db_user}
db_password = {password}
addons_path = /mnt/enterprise,/mnt/extra-addons,/usr/lib/python3/dist-packages/odoo/addons
data_dir = /var/lib/odoo
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
"""

# Default configuration values
DEFAULT_CONFIG = {
    'user': 'ubuntu',
    'ip': '',  # No default IP - will be detected if blank
    'odoo_port': '8069',
    'db_port': '5432',
    'db_user': 'odoo',
    'path_to_install': ''  # Will use execution path if blank
}

def print_usage():
    """Print usage message"""
    print("Usage: python3 create_client_setup.py <config_file>")
    print("Example: python3 create_client_setup.py odoo-17-setup.conf")
    print("\nConfig file format example:")
    print("client_name=acme")
    print("client_password=acme2025")
    print("user=root")
    print("ip=localhost")  # Empty IP - will be auto-detected
    print("odoo_port=8069")
    print("db_port=5432")
    print("db_user=odoo")
    print("path_to_install=/opt")

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

def normalize_install_path(config):
    """Create a normalized installation path from configuration"""
    client_name = config['client_name']
    base_path = os.path.normpath(config['path_to_install'])
    if not base_path:
        base_path = os.path.dirname(os.path.abspath(__file__))
    
    if f"{client_name}-odoo-17" in base_path:
        return os.path.normpath(base_path)
    else:
        return os.path.normpath(os.path.join(base_path, f"{client_name}-odoo-17"))

def load_config(config_file):
    """Load configuration from file with enhanced validation"""
    if not os.path.exists(config_file):
        print(f"Error: Config file not found: {config_file}")
        print(f"Tip: Create a config file using the template or run: python {sys.argv[0]} --create-config")
        sys.exit(1)

    # Use configparser for more robust parsing
    config = configparser.ConfigParser()

    # Add a default section since our config file doesn't have sections
    try:
        with open(config_file, 'r') as f:
            config_content = '[DEFAULT]\n' + f.read()
    except Exception as e:
        print(f"Error reading config file: {e}")
        print(f"Tip: Check file permissions and encoding")
        sys.exit(1)

    config.read_string(config_content)

    # Extract values with defaults
    result = dict(DEFAULT_CONFIG)

    required_fields = ['client_name', 'client_password']
    missing_fields = []

    for field in required_fields:
        if field not in config['DEFAULT'] or not config['DEFAULT'][field]:
            missing_fields.append(field)

    if missing_fields:
        print(f"Error: The following required fields are missing in the config file: {', '.join(missing_fields)}")
        print(f"Tip: Edit {config_file} and add values for these fields")
        sys.exit(1)

    client_name = config['DEFAULT']['client_name'].lower()
    if not client_name.isalnum():
        print("Error: client_name must contain only alphanumeric characters")
        print("Tip: Use letters and numbers only, no spaces or special characters")
        sys.exit(1)
    result['client_name'] = client_name

    result['client_password'] = config['DEFAULT']['client_password']

    # Optional values with defaults
    for key in DEFAULT_CONFIG.keys():
        if key in config['DEFAULT'] and config['DEFAULT'][key]:
            result[key] = config['DEFAULT'][key]

    # If IP is empty, determine it
    if not result['ip']:
        try:
            result['ip'] = get_public_ip()
        except Exception as e:
            print(f"Warning: Could not determine public IP: {e}")
            print("Using localhost as fallback")
            result['ip'] = 'localhost'

    if not result['path_to_install']:
        result['path_to_install'] = os.path.dirname(os.path.abspath(__file__))
    else:
        if not os.path.isabs(result['path_to_install']):
            result['path_to_install'] = os.path.abspath(os.path.join(
                os.path.dirname(os.path.abspath(__file__)),
                result['path_to_install']
            ))

    if not os.path.exists(result['path_to_install']):
        print(f"Error: Installation path does not exist: {result['path_to_install']}")
        print(f"Tip: Create the directory first or specify a different path")
        sys.exit(1)

    if not os.access(result['path_to_install'], os.W_OK):
        print(f"Error: No write permission to installation path: {result['path_to_install']}")
        print(f"Tip: Change directory permissions or specify a different path")
        sys.exit(1)

    # Validate password (at least 8 characters)
    if len(result['client_password']) < 8:
        print("Error: Password must be at least 8 characters long")
        print("Tip: Choose a stronger password with at least 8 characters")
        sys.exit(1)

    for port_key in ['http_port', 'https_port', 'longpolling_port']:
        if port_key in result and result[port_key]:
            try:
                port = int(result[port_key])
                if port < 1 or port > 65535:
                    raise ValueError("Port out of range")
                result[port_key] = str(port)  # Ensure it's a string
            except ValueError:
                print(f"Error: Invalid {port_key}: {result[port_key]}")
                print("Tip: Port must be a number between 1 and 65535")
                sys.exit(1)

    return result

def create_directory_structure(target_dir):
    """Create the directory structure for the client setup"""
    for dir_path in DIRS_TO_CREATE:
        full_path = os.path.join(target_dir, dir_path)
        if not os.path.exists(full_path):
            os.makedirs(full_path)
            print(f"Created directory: {full_path}")

def create_odoo_conf(config_path, config):
    """Create a default odoo.conf file"""
    os.makedirs(os.path.dirname(config_path), exist_ok=True)
    with open(config_path, 'w', encoding='utf-8') as file:
        file.write(DEFAULT_ODOO_CONF.format(
            password=config['client_password'],
            db_port=config['db_port'],
            db_user=config['db_user']
        ))
    print(f"Created odoo.conf: {config_path}")

def copy_template_files(source_dir, target_dir, config):
    """Copy and customize all template files"""
    client_name = config['client_name']
    print(f"Creating client setup for '{client_name}'...")

    # Create target directory if it doesn't exist
    if not os.path.exists(target_dir):
        os.makedirs(target_dir)
        print(f"Created directory: {target_dir}")

    # Create required subdirectories
    create_directory_structure(target_dir)

    # Copy all files from template
    for item in os.listdir(source_dir):
        source_item = os.path.join(source_dir, item)
        target_item = os.path.join(target_dir, item)

        # Skip if item is a directory in the directories to create list
        # (we've already created these with create_directory_structure)
        if os.path.isdir(source_item) and item in [d.split('/')[0] for d in DIRS_TO_CREATE]:
            continue

        if os.path.isdir(source_item):
            # Copy directory and its contents
            shutil.copytree(source_item, target_item, dirs_exist_ok=True)
            print(f"Copied directory: {item}")
        elif os.path.isfile(source_item):
            # Copy file
            shutil.copy2(source_item, target_item)
            print(f"Copied file: {item}")

            # Modify file content
            modify_file(target_item, config)

    # Copy SSL configuration template
    ssl_config_template = "ssl-config.conf.template"
    if os.path.exists(ssl_config_template):
        target_ssl_config = os.path.join(target_dir, ssl_config_template)
        shutil.copy(ssl_config_template, target_ssl_config)
        print(f"Copied {ssl_config_template}")
        # Process placeholders in SSL config template
        modify_file(target_ssl_config, config)

    # Copy SSL README
    ssl_readme = "SSL-README.md"
    if os.path.exists(ssl_readme):
        target_ssl_readme = os.path.join(target_dir, ssl_readme)
        shutil.copy(ssl_readme, target_ssl_readme)
        print(f"Copied {ssl_readme}")
        # Process placeholders in SSL README
        modify_file(target_ssl_readme, config)

    # Copy direct SSL config if not already copied in FILES_TO_COPY
    direct_ssl_config = "direct-ssl-config.conf"
    if os.path.exists(direct_ssl_config) and direct_ssl_config not in FILES_TO_COPY:
        target_direct_ssl = os.path.join(target_dir, direct_ssl_config)
        shutil.copy(direct_ssl_config, target_direct_ssl)
        print(f"Copied {direct_ssl_config}")
        # Process placeholders in direct SSL config
        modify_file(target_direct_ssl, config)

    # Create odoo.conf
    create_odoo_conf(os.path.join(target_dir, "config/odoo.conf"), config)

def fix_readme_installation_steps(file_path, config):
    """Fix the installation steps in README.md that might have line break issues"""
    with open(file_path, 'r', encoding='utf-8', errors='ignore') as file:
        content = file.read()

    client_name = config['client_name']
    user = config['user']
    ip = config['ip']
    base_path = os.path.normpath(config['path_to_install'])
    if not base_path:
        base_path = os.path.dirname(os.path.abspath(__file__))

    install_path = os.path.normpath(os.path.join(base_path, f"{client_name}-odoo-17"))

    # Create corrected installation steps
    corrected_steps = f'''1. Clone this repository to `{install_path}`:
   ```bash
   scp -r "<path to local install>/*" {user}@{ip}:{install_path}
   cd {install_path}
   ```

2. Place the Odoo Enterprise .deb file:
   ```bash
   scp -r "<path to enterprise .deb file>/odoo_17.0+e.latest_all.deb" {user}@{ip}:{install_path}
   ```'''

    # Find start of the clone section
    clone_pattern = r'1\. Clone this repository to `.+`:'
    if re.search(clone_pattern, content):
        # Replace the installation steps
        content = re.sub(
            r'1\. Clone this repository to `.+`:\s+```bash[\s\S]+?cd [^\n]+\s+```\s+2\. Place the Odoo Enterprise \.deb file:\s+```bash[\s\S]+?```',
            corrected_steps.replace('\\', r'\\'),  # Escape backslashes to avoid bad escape errors
            content,
            flags=re.DOTALL
        )

    # Write the corrected content back to the file
    with open(file_path, 'w', encoding='utf-8') as file:
        file.write(content)

    print(f"Fixed installation steps in README.md")

def update_docker_compose(file_path, config):
    """Update the docker-compose.yml with custom ports and container names"""
    client_name = config['client_name']
    client_password = config['client_password']

    with open(file_path, 'r', encoding='utf-8', errors='ignore') as file:
        content = file.read()

    # Update Odoo port
    content = re.sub(
        r'ports:\s+- "0.0.0.0:\d+:\d+"',
        f'ports:\n      - "0.0.0.0:{config["odoo_port"]}:8069"',
        content
    )

    # Add filestore volume mapping if it doesn't exist
    if './filestore:/var/lib/odoo/filestore' not in content:
        volumes_pattern = r'(volumes:\s+(?:- .*\n\s+)+)'
        volumes_replacement = r'\1      - ./filestore:/var/lib/odoo/filestore\n    '
        content = re.sub(volumes_pattern, volumes_replacement, content)

    # Update database port if needed
    if config['db_port'] != '5432':
        content = content.replace('PORT=5432', f'PORT={config["db_port"]}')

    # Update database user if specified
    if config['db_user'] != 'odoo':
        content = content.replace('POSTGRES_USER=odoo', f'POSTGRES_USER={config["db_user"]}')
        content = content.replace('USER=odoo', f'USER={config["db_user"]}')

    # Update passwords
    content = content.replace('{template_password}', client_password)

    with open(file_path, 'w', encoding='utf-8') as file:
        file.write(content)

    print(f"Updated docker-compose.yml with custom settings")

def update_staging_script(file_path, config):
    """Update staging.sh with specific configuration values"""
    with open(file_path, 'r', encoding='utf-8', errors='ignore') as file:
        content = file.read()

    # Ensure server configuration parameters are correctly set
    client_name = config['client_name']
    install_path = normalize_install_path(config)

    # Explicitly replace configuration values in staging.sh header
    content = re.sub(r'INSTALL_DIR="[^"]*"', f'INSTALL_DIR="{install_path}"', content)
    content = re.sub(r'SERVER_IP=[^\n]*', f'SERVER_IP={config["ip"]}', content)
    content = re.sub(r'BASE_PORT=[^\n]*', f'BASE_PORT={config["odoo_port"]}', content)
    content = re.sub(r'POSTGRES_PORT=[^\n]*', f'POSTGRES_PORT={config["db_port"]}', content)

    with open(file_path, 'w', encoding='utf-8') as file:
        file.write(content)

    print(f"Updated server configuration in staging.sh")

def modify_file(file_path, config):
    """Replace all instances of template name and password with the new client values"""
    if not os.path.exists(file_path):
        print(f"Warning: File does not exist: {file_path}")
        return

    client_name = config['client_name']
    client_password = config['client_password']
    install_path = normalize_install_path(config)
    path_to_install = os.path.normpath(config['path_to_install'])

    # Read file content
    with open(file_path, 'r', encoding='utf-8', errors='ignore') as file:
        content = file.read()

    print(f"DEBUG: In file {file_path}")
    print(f"DEBUG: Path to install value: {path_to_install}")
    print(f"DEBUG: Number of {path_to_install} occurrences before replacement: {content.count(path_to_install)}")
    print(f"DEBUG: Install path: {install_path}")

    # Apply client name replacements in different formats
    client_title = client_name.title()

    content = content.replace('{client_name}', client_name)
    content = content.replace('{client_password}', client_password)

    # Replace container names
    content = content.replace('odoo17-{client_name}', f'odoo17-{client_name}')
    content = content.replace('db-{client_name}', f'db-{client_name}')

    # Replace database names
    content = content.replace('postgres_{client_name}', f'postgres_{client_name}')

    # Replace project title
    content = content.replace('Odoo 17 Enterprise - {client_name}', f'Odoo 17 Enterprise - {client_title}')
    content = content.replace('Installation Script for {client_name}', f'Installation Script for {client_title}')
    content = content.replace('installation of Odoo 17 Enterprise for {client_name}',
                     f'installation of Odoo 17 Enterprise for {client_title}')

    # Replace specific configuration values
    content = content.replace('{ip}', config['ip'])
    content = content.replace('{odoo_port}', config['odoo_port'])
    content = content.replace('{db_port}', config['db_port'])

    if file_path.endswith('install.sh') or file_path.endswith('backup.sh') or file_path.endswith('git_panel.sh') or file_path.endswith('staging.sh'):
        lines = content.split('\n')
        for i, line in enumerate(lines):
            if line.strip().startswith('INSTALL_DIR='):
                original_line = line
                lines[i] = f'INSTALL_DIR="{install_path}"'
                print(f"DEBUG: Original INSTALL_DIR line: {original_line}")
                print(f"DEBUG: New INSTALL_DIR line: {lines[i]}")
                
                if i+1 < len(lines) and 'sed' in lines[i+1] and 'INSTALL_DIR' in lines[i+1]:
                    print(f"DEBUG: Found sed command that might modify INSTALL_DIR: {lines[i+1]}")
                    lines[i+1] = ''
                break
        
        content = '\n'.join(lines)
        
        print(f"DEBUG: Skipping general path replacement for script file {file_path}")
    else:
        content = content.replace('{path_to_install}', path_to_install)

    # Update DB_USER if needed
    if config['db_user'] != 'odoo':
        content = re.sub(r'DB_USER="odoo"', f'DB_USER="{config["db_user"]}"', content)

    occurrences = content.count(path_to_install)
    print(f"DEBUG: Number of {path_to_install} occurrences after replacement: {occurrences}")

    if occurrences > 1:
        # Find the lines containing the duplicated path
        lines = content.split('\n')
        duplicate_lines = [line for line in lines if path_to_install in line]
        print(f"ERROR: Found duplicate path in file {file_path}:")
        for i, line in enumerate(duplicate_lines):
            print(f"  Line {i+1}: {line}")
        print("Terminating to prevent path duplication.")
        sys.exit(1)

    # Write modified content back to file
    with open(file_path, 'w', encoding='utf-8') as file:
        file.write(content)

    print(f"Modified: {file_path}")

    # Verify the final content in the file to catch any discrepancies
    if file_path.endswith('install.sh'):
        print("DEBUG: Final verification of install.sh file:")
        with open(file_path, 'r', encoding='utf-8') as file:
            install_content = file.read()
            install_lines = install_content.split('\n')
            for i, line in enumerate(install_lines):
                if "INSTALL_DIR" in line:
                    print(f"  Line {i+1}: {line}")

    # Special handling for specific files
    if file_path.endswith('README.md'):
        fix_readme_installation_steps(file_path, config)
    elif file_path.endswith('docker-compose.yml'):
        update_docker_compose(file_path, config)
    elif file_path.endswith('staging.sh'):
        update_staging_script(file_path, config)

def create_sample_config(filename):
    """Create a sample configuration file"""
    with open(filename, 'w', encoding='utf-8') as file:
        file.write("""# Odoo 17 Setup Configuration
# Required parameters
client_name=acme
client_password=acme2025

# Optional parameters (leave blank for defaults)
user=root
ip=
odoo_port=8069
db_port=5432
db_user=odoo
path_to_install=
""")
    print(f"Created sample configuration file: {filename}")

def main():
    """Main function"""
    if len(sys.argv) != 2:
        print_usage()
        if len(sys.argv) == 1:
            # Check if config file already exists
            if os.path.exists('odoo-17-setup.conf'):
                print("\nUsing existing configuration file: odoo-17-setup.conf")
                config_file = 'odoo-17-setup.conf'
            else:
                # Create a sample config file
                create_sample_config('odoo-17-setup.conf')
                print("\nA sample configuration file has been created: odoo-17-setup.conf")
                print("Edit this file and run the script again.")
                sys.exit(1)
        else:
            sys.exit(1)
    else:
        config_file = sys.argv[1]

    # Load the config file
    config = load_config(config_file)

    # Define the template directory - using {client_name}-odoo-17-setup
    current_dir = os.path.dirname(os.path.abspath(__file__))
    template_dir = os.path.join(current_dir, TEMPLATE_NAME)

    # Define the target directory for the new client
    if config['path_to_install']:
        base_path = os.path.normpath(config['path_to_install'])
    else:
        base_path = current_dir

    target_dir = normalize_install_path(config)
    print(f"DEBUG: Installation directory: {target_dir}")

    # Check if target directory already exists
    if os.path.exists(target_dir):
        print(f"Directory {target_dir} already exists. Operation cancelled")
        sys.exit(0)

    # Check if template directory exists
    if not os.path.exists(template_dir):
        print(f"Error: Template directory not found: {template_dir}. This directory should be named: " + "{client_name}-odoo-17-setup")
        sys.exit(1)

    # Copy template files and customize them
    copy_template_files(template_dir, target_dir, config)

    deb_file = os.path.join(current_dir, "odoo_17.0+e.latest_all.deb")
    if os.path.exists(deb_file):
        shutil.copy2(deb_file, target_dir)
        print(f"Copied Odoo Enterprise .deb file to {target_dir}")

    print(f"\nClient setup for '{config['client_name']}' created successfully!")
    print(f"Directory: {target_dir}")
    print(f"\nConfiguration used:")
    for key, value in config.items():
        print(f"  {key}: {value}")

    print(f"\nNext steps:")
    print(f"1. Review the generated files in {target_dir}")
    print(f"2. Make any additional customizations needed for {config['client_name']}")
    print(f"3. Deploy using the instructions in README.md")

if __name__ == "__main__":
    main()
