
# Odoo 17 Parameterization System

This system provides a two-phase deployment approach for Odoo 17:

1. **Setup Generation Phase**: Create a customized installer package for a specific client
2. **Deployment Phase**: Transfer the installer to the target system and execute it

## How It Works

### Phase 1: Setup Generation

The `create-odoo-setup.py` script takes a configuration file and:

1. Creates a new directory structure at `{path_to_install}/{client_name}-odoo17-setup`
2. Copies all template files from the source directory to this new location
3. Replaces placeholder variables like `{client_name}` with actual values throughout all files
4. Generates a ready-to-deploy installation package

### Phase 2: Deployment

The generated installer can be:

1. Transferred to the target system (`scp -r`)
2. Executed with `install.sh` to deploy a fully configured Odoo 17 instance

## Configuration Parameters

The following variables are used in the template files:

| Parameter | Description | Default |
|-----------|-------------|---------|
| `client_name` | Client name (for DB names, containers, etc.) | *Required* |
| `client_password` | Primary password (admin, database) | *Required* |
| `odoo_port` | Odoo web port | 8069 |
| `db_port` | PostgreSQL port | 5432 |
| `db_user` | Database username | odoo |
| `{odoo_db_name}` | Odoo database name | Same as client_name |
| `path_to_install` | Target installation directory | Current directory |
| `user` | Server username | Auto-detected |
| `ip` | Server IP address | Auto-detected |

## Files Modified by Parameterization

The script customizes the following files:

- `docker-compose.yml` - Container configurations with proper naming
- `install.sh` - Installation script with client-specific settings 
- `backup.sh` - Backup/restore utility with correct paths
- `staging.sh` - Staging environment management
- `git_panel.sh` - Git management utility
- `config/odoo.conf` - Odoo server configuration
- `README.md` - Documentation with client-specific information

## Step-by-Step Usage

### 1. Create Configuration File

Create a file named `odoo-setup.conf` with client details:

```
client_name=acme
client_password=Secret2025
odoo_port=8069
db_port=5432
db_user=odoo
path_to_install=/opt
```

### 2. Run the Parameterization Script

```bash
python3 create-odoo-setup.py odoo-setup.conf
```

This generates a complete installer at `/opt/acme-odoo17-setup`

### 3. Transfer the Setup to Target System

```bash
# From your development system:
scp -r /opt/acme-odoo17-setup/* user@target-server:/opt/acme-odoo17-setup
```

### 4. Download Enterprise Files

```bash
# On the target system:
scp -r "path/to/odoo_17.0+e.latest_all.deb" user@target-server:/opt/acme-odoo17-setup
```

### 5. Run Installation

```bash
# On the target system:
cd /opt/acme-odoo17-setup
chmod +x install.sh && sudo -E ./install.sh
```

The installer will:
- Set up Docker containers
- Configure PostgreSQL
- Deploy Odoo with enterprise modules
- Create startup services
- Configure backup schedules

## Advanced Usage

### Auto-Detection

If you omit `user` or `ip` from the config file, the script will attempt to auto-detect these values.

### Multiple Client Setups

To create setups for multiple clients:

```bash
# Client 1
python3 create-odoo-setup.py client1-config.conf

# Client 2
python3 create-odoo-setup.py client2-config.conf
```

Each client gets an isolated installation with separate:
- Databases
- Docker containers
- Configuration files
- Backup locations

## Troubleshooting

- If the script fails to detect your IP, specify it manually in the config file
- Ensure the `odoo_17.0+e.latest_all.deb` file is available before running the install script
- Check permissions if you encounter access issues when running the install script
