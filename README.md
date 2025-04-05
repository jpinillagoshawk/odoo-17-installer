# Odoo 17 Enterprise Installer with SSL/HTTPS Support

A comprehensive installer for Odoo 17 Enterprise that automates deployment with Docker, includes SSL/HTTPS configuration, and provides robust backup and maintenance utilities.

## Project Overview

This project creates customized Odoo 17 Enterprise deployment packages for clients. It provides:

- Automated installation with pre-configured Docker setup
- SSL/HTTPS configuration (direct SSL or reverse proxy with Nginx)
- Comprehensive backup and restore functionality
- Client-specific setups with parameter templating
- Maintenance and monitoring utilities

## Directory Structure

```
odoo_17_installer/
├── {client_name}-odoo-17-setup/  # Template directory with placeholder files
│   ├── README.md                 # Usage instructions for end users
│   ├── SSL-README.md             # SSL setup instructions
│   ├── backup.sh                 # Backup/restore utility
│   ├── config/                   # Configuration files
│   ├── direct-ssl-config.conf    # SSL configuration for direct SSL
│   ├── docker-compose.yml        # Docker container configuration
│   ├── install.sh                # Main installation script
│   ├── requirements.txt          # Python dependencies
│   ├── ssl-config.conf.template  # SSL configuration template
│   ├── ssl-setup.sh              # SSL configuration script
│   └── staging.sh                # Staging environment setup
├── create_client_setup.py        # Client setup generator script
└── odoo-17-setup.conf            # Sample configuration file
```

## Key Components

### 1. Client Setup Generator (`create_client_setup.py`)

This script creates customized Odoo 17 setup packages for specific clients:

- Replaces placeholders like `{client_name}` and `{client_password}` in all template files
- Creates directory structure for client-specific deployment
- Processes configuration templates for SSL, Docker, and Odoo

**Usage:**
```bash
python create_client_setup.py <config_file>
```

**Configuration File Format:**
```
client_name=acme
client_password=acme2024
user=ubuntu
ip=195.190.194.108
odoo_port=8069
db_port=5432
db_user=odoo
path_to_install=/opt
```

### 2. Installation Script (`install.sh`)

The main installation script that:

- Validates system requirements
- Sets up Docker containers for Odoo and PostgreSQL
- Configures the database and Odoo parameters
- Sets up scheduled backups
- Provides colorful, user-friendly console output
- Includes pre-installation analysis and validation

### 3. SSL Setup (`ssl-setup.sh`)

Handles SSL certificate acquisition and configuration with support for:

- Let's Encrypt certificates (automatic)
- Manual certificates (user-provided)
- Direct SSL (Odoo handles SSL)
- Proxy SSL (Nginx as reverse proxy)

Uses configuration from `ssl-config.conf` and template files.

### 4. Backup Utility (`backup.sh`)

Provides backup and restore functionality:

- Creates daily and monthly backups
- Backs up database and filestore
- Can restore from local backups or Odoo.sh exports
- Includes backup rotation and cleanup

## Template Processing

The system uses a templating approach:

1. Template files use placeholders like `{client_name}` and `{client_password}`
2. The `create_client_setup.py` script replaces these with actual values
3. Key template files include:
   - `direct-ssl-config.conf`
   - `ssl-config.conf.template`
   - `docker-compose.yml`
   - Configuration files in the `config/` directory

## Deployment Process

1. Create client configuration file (e.g., `client-setup.conf`)
2. Generate client-specific setup:
   ```bash
   python create_client_setup.py client-setup.conf
   ```
3. Deploy to server:
   ```bash
   scp -r client_name-odoo-17-setup/ user@server:/opt/
   ```
4. Run installation script:
   ```bash
   cd /opt/client_name-odoo-17-setup
   ./install.sh
   ```
5. Configure SSL (if needed):
   ```bash
   ./ssl-setup.sh
   ```

## Backup and Restore

### Creating Backups
```bash
./backup.sh backup daily    # Create daily backup
./backup.sh backup monthly  # Create monthly backup
```

### Restoring Backups
```bash
./backup.sh restore                      # Interactive restore
./backup.sh restore /path/to/backup.zip  # Restore specific backup
```

The restore functionality works with:
- Local backups created by the backup.sh script
- Odoo.sh exported backups (containing dump.sql and filestore directory)

## Modifying the Code

### Adding New Template Files

1. Add the file to the template directory (`{client_name}-odoo-17-setup/`)
2. Update `FILES_TO_COPY` in `create_client_setup.py` if needed
3. Use `{client_name}` and `{client_password}` placeholders for dynamic values

### Modifying Installation Process

The `install.sh` script is structured in modular functions:

- `check_requirements()`: System requirement validation
- `setup_files()`: File and directory setup
- `configure_docker()`: Docker configuration
- `create_backup_script()`: Backup script setup

Edit the relevant function to modify specific aspects of installation.

### SSL Configuration

The SSL setup is controlled by:

1. `ssl-config.conf.template` - Main configuration template
2. `direct-ssl-config.conf` - Direct SSL configuration template
3. `ssl-setup.sh` - Implementation script with functions:
   - `configure_direct_ssl()`: Configure Odoo for direct SSL
   - `configure_nginx()`: Configure Nginx as reverse proxy
   - `obtain_certificate()`: Certificate acquisition (Let's Encrypt or manual)

## Implementation Details

### Parameter Substitution

- Template files use `{client_name}`, `{client_password}`, and other placeholders
- The `modify_file()` function in `create_client_setup.py` handles replacements
- Special files like `ssl-config.conf.template` have custom processing

### SSL Configuration Logic

1. User runs `ssl-setup.sh`
2. Script loads configuration from `ssl-config.conf`
3. Verifies system requirements
4. Obtains SSL certificate (Let's Encrypt or manual)
5. Configures SSL based on type:
   - Direct: Updates Odoo config using `direct-ssl-config.conf`
   - Proxy: Sets up Nginx as reverse proxy

### Backup Strategy

- Backups include database dumps and filestore content
- Rotation: Daily backups kept for 7 days, monthly for 6 months
- Database restored using appropriate PostgreSQL tool based on format

## Troubleshooting

Common issues and solutions:

1. **Certificate acquisition failures:**
   - Check port 80 is open for HTTP challenge
   - Verify domain DNS resolution

2. **Database restore issues:**
   - Ensure PostgreSQL version compatibility
   - Check for sufficient disk space

3. **Docker issues:**
   - Verify Docker and Docker Compose installation
   - Check for port conflicts

## License

[Specify your license here]

## Contributing

[Specify contribution guidelines] 