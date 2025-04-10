# Odoo 17 Enterprise - {client_name} Installation

_Last Updated: January 2025_

This repository contains the Docker-based installation of Odoo 17 Enterprise for {client_name}. The setup includes automated installation, backup procedures, and maintenance guidelines.

## 📋 Table of Contents
- [Quick Start](#quick-start)
- [System Requirements](#system-requirements)
- [Installation](#installation)
- [Directory Structure](#directory-structure)
- [Backup Management](#backup-management)
- [Staging Management](#staging-management)
- [Git Management](#git-management)
- [Configuration](#configuration)
- [Maintenance](#maintenance)
- [Troubleshooting](#troubleshooting)
- [Security](#security)
- [Support](#support)

## Quick Start 🚀

```bash
# 1. Clone and install

# From your local pc cmd window:
scp -r "<path to local install>/*" user@195.190.194.108:/{client_name}-odoo-17 
# From your remote ubuntu environment:
cd /{client_name}-odoo-17 scp -r "<path to enterprise .deb file>/odoo_17.0+e.latest_all.deb" user@195.190.194.108:/{client_name}-odoo-17 chmod +x install.sh && sudo -E ./install.sh

# 2. Create backup
sudo ./backup.sh backup daily

# 3. Create staging (optional)
sudo ./staging.sh create
```

## System Requirements 🔧

- **Operating System**: Linux/Unix-based system
- **Docker**: Engine 20.10.x+ and Compose v2.x+
- **Memory**: 4GB minimum (8GB recommended)
- **Storage**: 20GB+ free space
- **Network**: Port 8069 available
- **Python**: 3.8 or newer (for staging management)

## Installation 📥

<details>
<summary>Detailed Installation Steps</summary>

1. Download odoo_17.0+e.latest_all.deb and place it into <path_to_install>/{client_name}-odoo-17/
   e.g. windows command to send the file through ssh with cmd:
   ```bash
   pscp -pw <ssh_password> <path_to_local_.deb_file> {user}@{ip}:{install_path}
   ```
   Place the Odoo Enterprise .deb file:
   ```bash
   scp -r "<path to enterprise .deb file>/odoo_17.0+e.latest_all.deb" {user}@{ip}:/{client_name}-odoo-17
   ```
2. Run installation:
   ```bash
   chmod +x install.sh && sudo -E ./install.sh
3. Configure SSL (if needed):
   ```bash
   chmod +x ssl-setup.sh && sudo -E ./ssl-setup.sh
   ```
</details>

## Directory Structure 📁

```
/{client_name}-odoo-17/
├── addons/            # Custom addons
├── backups/           # Backup storage
│   ├── daily/         # Daily backups
│   └── monthly/       # Monthly backups
├── config/            # Configuration files
│   └── odoo.conf      # Odoo configuration
├── enterprise/        # Enterprise addons
├── logs/              # Log files
├── staging/           # Staging environments
│   └── staging/       # Default staging instance
├── volumes/           # Docker volumes
│   ├── odoo-data/     # Odoo filestore
│   └── postgres-data/ # PostgreSQL data
├── backup.sh          # Backup/restore script
├── docker-compose.yml # Docker services config
├── install.sh         # Installation script
├── staging.py         # Staging management script
└── README.md          # This file
```

## Backup Management 💾

<details>
<summary>Backup Creation and Management</summary>

### Creating Backups
```bash
# Create daily backup
sudo ./backup.sh backup daily

# Create monthly backup
sudo ./backup.sh backup monthly
```

**Backup Contents**:
- Database dump (PostgreSQL custom format)
- Complete filestore directory
- Filestore path list for cleanup

**Storage Locations**:
- Daily: `/{client_name}-odoo-17/backups/daily/backup_YYYYMMDD_HHMMSS.zip`
- Monthly: `/{client_name}-odoo-17/backups/monthly/backup_YYYYMMDD_HHMMSS.zip`

### Automated Schedule
- Daily: 3:00 AM (keeps 7 days)
- Monthly: 2:00 AM on 1st (keeps 6 months)
</details>

<details>
<summary>Restore Procedures</summary>

### Restore Options

1. Interactive (Recommended):
   ```bash
   sudo ./backup.sh restore
   ```

2. Direct Path:
   ```bash
   sudo ./backup.sh restore /{client_name}-odoo-17/backups/daily/backup_YYYYMMDD_HHMMSS.zip
   ```

### Backup Management
```bash
# List backups
sudo ./backup.sh list

# Cleanup old backups
sudo find /{client_name}-odoo-17/backups/daily /{client_name}-odoo-17/backups/monthly -type f -name "backup_*.zip" ! -name "$(ls -t /{client_name}-odoo-17/backups/daily/backup_*.zip /{client_name}-odoo-17/backups/monthly/backup_*.zip 2>/dev/null | head -n1 | xargs basename)" -delete
```
</details>

## Staging Management 🔄

<details>
<summary>Staging Commands and Structure</summary>

The installation includes a staging management system that allows you to create, manage, and destroy staging environments for development and testing purposes.

### Staging Commands

1. Create staging environments:
```bash
# Create first staging (named "staging")
sudo ./staging.sh create

# Create additional staging (auto-named "staging-2", etc.)
sudo ./staging.sh create

# Create staging with specific name
sudo ./staging.sh create staging-xxx
```

2. List and manage stagings:
```bash
# List all staging environments
sudo ./staging.sh list

# Start a staging
sudo ./staging.sh start staging

# Stop a staging
sudo ./staging.sh stop staging

# Delete a staging
sudo ./staging.sh delete staging

# Update staging from production
sudo ./staging.sh update staging

# Clean up staging environments
sudo ./staging.sh cleanup all          # Remove all staging environments
sudo ./staging.sh cleanup staging-2    # Remove specific staging environment
```

### Port Allocation

Staging environments use automatic port allocation:
- First staging (staging): 8069 (web), 8072 (longpolling), 5432 (postgres)
- Additional stagings: Ports increment by 10 for each instance
  - staging-2: 8079, 8082, 5442
  - staging-3: 8089, 8092, 5452
  etc.

### Directory Structure

Each staging environment is created under `/{client_name}-odoo-17/staging/` with the following structure:
```
/{client_name}-odoo-17/staging/
├── staging/           # First staging environment
│   ├── config/       # Configuration files
│   ├── enterprise/   # Enterprise addons
│   ├── addons/      # Custom addons
│   ├── volumes/     # Docker volumes
│   │   ├── odoo-data/     # Filestore
│   │   └── postgres-data/ # Database
│   ├── logs/        # Log files
│   └── docker-compose.yml
└── staging-2/       # Second staging environment
    └── ...
```

### Important Notes
- Each staging has isolated:
  - Docker containers
  - Database
  - Port allocations
  - Configuration
  - Volume data
- Stagings are production clones
- Port checks are automatic
</details>

## Git Management 🔄

<details>
<summary>Git Commands and Integration</summary>

The installation includes a git management system similar to odoo.sh that allows you to manage your custom addons using git, automatically create branches for staging environments, and synchronize changes.

### Git Panel Commands

1. Setup git repository:
```bash
sudo ./git_panel.sh setup
```

2. Check status of git repository:
```bash
sudo ./git_panel.sh status
```

3. Fetch remote changes:
```bash
sudo ./git_panel.sh fetch
```

4. Push local changes:
```bash
sudo ./git_panel.sh push
```

5. Pull changes from a branch:
```bash
sudo ./git_panel.sh pull [branch]
```

6. List available branches:
```bash
sudo ./git_panel.sh list-branches
```

### Integration with Staging Environments

- When creating a new staging environment, a corresponding git branch is automatically created.
- When deleting a staging environment, you will be warned if there are uncommitted changes in the git branch.
- Each staging environment's addons directory is associated with its respective git branch.
- The main installation always corresponds to the "main" branch.

</details>

## Configuration ⚙️

<details>
<summary>Database and Service Configuration</summary>

### Database Settings
```yaml
Database Name: postgres_{client_name}
User: odoo
Password: {client_password}
Admin Password: {client_password}
```

### Docker Services
```yaml
Odoo Web:
  Container: odoo17-{client_name}
  Port: 8069
  Paths:
    - Enterprise: /mnt/enterprise
    - Custom: /mnt/extra-addons
  
PostgreSQL:
  Container: db-{client_name}
  Version: 15
  Port: 5432
```
</details>

## Maintenance 🛠️

<details>
<summary>Maintenance Procedures</summary>

### Updating Odoo
1. Stop the containers:
   ```bash
   cd /{client_name}-odoo-17    docker-compose down
   ```

2. Update the image in docker-compose.yml
3. Pull new images:
   ```bash
   docker-compose pull
   ```

4. Start services:
   ```bash
   docker-compose up -d
   ```

### Log Management
- Location: `/{client_name}-odoo-17/logs/`
- Rotation: 100MB max, 3 files

### Database Maintenance
```bash
# Access PostgreSQL
docker exec -it db-{client_name} psql -U odoo postgres_{client_name}

# Common queries
SELECT pg_size_pretty(pg_database_size('postgres_{client_name}'));
SELECT * FROM pg_stat_activity;
```
</details>

## Troubleshooting 🔍

<details>
<summary>Common Issues and Solutions</summary>

### Docker Issues
```bash
# Service status
docker-compose ps
docker-compose logs -f web
docker-compose logs -f db

# Network check
docker exec odoo17-{client_name} ping db
```

### Permission Issues
```bash
sudo chown -R 101:101 /{client_name}-odoo-17/volumes/odoo-data
sudo chmod -R 777 /{client_name}-odoo-17/volumes/odoo-data
```

### Database Connection
- Check container status
- Verify passwords in:
  - docker-compose.yml
  - odoo.conf
  - Environment variables
</details>

## Security 🔐

<details>
<summary>Security Guidelines</summary>

1. **File Permissions**
   - UID 101 (odoo user) ownership
   - Restricted backup access

2. **Network Security**
   - Firewall port 8069
   - Use SSL reverse proxy

3. **Password Management**
   - Change defaults
   - Use strong passwords
   - Secure storage
</details>

## Support 📞

- **Documentation**
  - [Odoo](https://www.odoo.com/documentation/17.0/)
  - [Docker](https://docs.docker.com/)
  - [PostgreSQL](https://www.postgresql.org/docs/15/)

- **Contact**
  - Technical Support (as of January 2025): javier.pinilla@goshawkanalytics.com
  - Emergency: jorge.huescar@goshawkanalytics.com

## License 📄

This installation is covered by your Odoo Enterprise subscription. Ensure compliance with terms and conditions.

## Change Log 📝

- 2025-01: Initial documentation
- [Add future changes here]    