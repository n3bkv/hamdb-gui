# HamDB GUI V1.0

A modern web interface for K3NG's HamDB amateur radio callsign database lookup tool. Features a responsive design, real-time, local FCC database lookups, and comprehensive search capabilities perfect for Field Day, contests, and daily amateur radio operations.

## Features

### Comprehensive Search Capabilities
- **Callsign Lookup** - Direct FCC database queries for any amateur radio callsign
- **Wildcard Search** - Pattern matching with `%` wildcard (e.g., `W1A%` finds all callsigns starting with W1A)
- **Geographic Search** - Find all amateur operators in a specific ZIP code
- **Name Search** - Search by operator last name
- **Real-time Results** - Fast database queries with optimized indexing

### Modern Web Interface
- **Responsive Design** - Works perfectly on desktop, tablet, and mobile devices
- **Modern UI** - Glassmorphism design with smooth animations
- **Tabbed Interface** - Easy switching between search types
- **Real-time Validation** - Input formatting and error handling
- **Loading Indicators** - Visual feedback during database queries
- **Mobile-First** - Optimized for use during portable operations

### Professional Infrastructure
- **Auto-Start Services** - All components start automatically on boot
- **Health Monitoring** - Built-in API health checks and status monitoring
- **Automatic Updates** - Daily FCC database updates via cron
- **Security Hardened** - Minimal privileges, firewall configuration, security headers
- **Production Ready** - Systemd service, Nginx reverse proxy, proper logging
- **Backup Tools** - Configuration backup and restore utilities

### Amateur Radio Focused
- **FCC Database** - Complete, current amateur radio license database
- **Contest Ready** - Fast lookups perfect for contests and DXpeditions  
- **Field Day Optimized** - Network accessible from any device
- **Emergency Communications** - Reliable callsign verification for emergency nets
- **QSL Information** - Complete operator information including address data

## Quick Start

### Prerequisites
- Raspberry Pi (3B+ or newer recommended) or Debian-based Linux system
- Internet connection for initial setup and database updates
- sudo privileges

### One-Line Installation
```bash
curl -fsSL https://raw.githubusercontent.com/n3bkv/hamdb-gui/Ham_DB_Gui.sh | bash
```

### Manual Installation
```bash
# Download the installer
wget https://raw.githubusercontent.com/n3bkv/hamdb-gui/Ham_DB_Gui.sh

# Make executable
chmod +x Ham_DB_Gui.sh

# Run installation
./Ham_DB_Gui.sh
```

### What Gets Installed
The installer automatically:
1. **Updates system packages** and installs dependencies (Node.js, MariaDB, Nginx)
2. **Downloads K3NG's HamDB** script from the official GitHub repository
3. **Configures database** with secure authentication and proper permissions
4. **Creates web interface** with professional responsive design
5. **Sets up services** with systemd, Nginx reverse proxy, and security hardening
6. **Initializes FCC database** (optional - downloads ~160MB of current data)
7. **Configures automatic updates** for daily FCC database synchronization

## Usage

### Accessing the Interface
After installation, access your HamDB GUI at:
- **Local**: `http://localhost/`
- **Network**: `http://[your-pi-ip]/`
- **Direct**: `http://[your-pi-ip]:8080/`

### Search Types

#### Callsign Lookup
```
Search: W1AW
Result: ARRL HQ OPERATORS CLUB, 225 MAIN ST, NEWINGTON, CT 06111
```

#### Wildcard Search
```
Search: W1A%
Results: All callsigns beginning with W1A (W1AA, W1AB, W1AC, etc.)
```

#### ZIP Code Search
```
Search: 06111
Results: All amateur operators in Newington, CT area
```

#### Last Name Search
```
Search: SMITH
Results: All amateur operators with last name SMITH
```

### CLI Usage
The underlying HamDB CLI is also available:
```bash
# Direct callsign lookup
hamdb W1AW

# Wildcard search
hamdb like W1A%

# ZIP code search
hamdb zipcode 06111

# Last name search
hamdb lastname SMITH

# Show database statistics
hamdb count

# Update database
hamdb update
```

## Administration

### Service Management
```bash
# Check service status
sudo systemctl status hamdb-gui

# View real-time logs
sudo journalctl -u hamdb-gui -f

# Restart service
sudo systemctl restart hamdb-gui

# Stop/start service
sudo systemctl stop hamdb-gui
sudo systemctl start hamdb-gui
```

### Database Management
```bash
# Update FCC database (manual)
sudo /opt/hamdb/update_database.sh

# Check database statistics
sudo -u hamdb /usr/local/bin/hamdb count

# Test database connectivity
sudo -u hamdb /usr/local/bin/hamdb W1AW
```

### System Monitoring
```bash
# Complete system status check
sudo /opt/hamdb/check_status.sh

# Check API health
curl http://localhost:8080/api/health

# View database statistics via API
curl http://localhost:8080/api/stats
```

### Backup and Restore
```bash
# Backup configuration
sudo /opt/hamdb/backup_config.sh

# View available backups
ls -la ~/hamdb-backups/

# Restore from backup (manual process)
# Extract backup and copy files to appropriate locations
```

## File Structure

```
/opt/hamdb/                     # Main application directory
├── .hamdb.cnf                  # Database configuration (credentials)
├── bin/hamdb                   # HamDB CLI binary
├── web/                        # Web application files
│   ├── index.html              # Main web interface
│   ├── server.js               # Node.js API server
│   ├── package.json            # Node.js dependencies
│   └── node_modules/           # Installed packages
├── logs/                       # Application logs
│   └── update.log              # Database update logs
├── update_database.sh          # Database update script
├── check_status.sh             # System status checker
└── uninstall.sh                # Complete removal script

/usr/local/bin/hamdb            # System-wide HamDB CLI
/etc/systemd/system/hamdb-gui.service  # Service configuration
/etc/nginx/sites-available/hamdb-gui   # Nginx configuration
```

## Configuration

### Database Configuration
Database credentials are stored in `/opt/hamdb/.hamdb.cnf`:
```bash
#!/bin/sh
MYSQLUSERNAME="hamdbuser"
MYSQLPASSWD="hamdb123secure"
```

### Web Service Configuration
The Node.js service runs on port 8080 and is reverse-proxied through Nginx on port 80.

**Environment Variables:**
- `PORT=8080` - Web service port
- `HOME=/opt/hamdb` - HamDB user home directory
- `NODE_ENV=production` - Production mode

### Automatic Updates
Daily database updates are scheduled via cron at 2:30 AM:
```bash
# View/edit cron schedule
sudo crontab -u hamdb -l
sudo crontab -u hamdb -e
```

### Nginx Configuration
- Reverse proxy from port 80 to 8080
- Security headers enabled
- Gzip compression
- Health check endpoint at `/health`

## Troubleshooting

### Common Issues

#### Service Won't Start
```bash
# Check service status and logs
sudo systemctl status hamdb-gui
sudo journalctl -u hamdb-gui -n 50

# Common fixes
sudo systemctl restart mariadb
sudo systemctl restart hamdb-gui
```

#### Database Connection Errors
```bash
# Test database connectivity
sudo -u hamdb mysql --defaults-file=/opt/hamdb/.hamdb.cnf -e "SHOW DATABASES;"

# Reset database password if needed
sudo mysql -e "ALTER USER 'hamdbuser'@'localhost' IDENTIFIED BY 'newpassword';"
# Update /opt/hamdb/.hamdb.cnf with new password
```

#### Web Interface Not Accessible
```bash
# Check if services are running
sudo systemctl status nginx hamdb-gui mariadb

# Test direct API access
curl http://localhost:8080/api/health

# Check firewall
sudo ufw status
```

#### Database Empty or Outdated
```bash
# Check record count
sudo -u hamdb /usr/local/bin/hamdb count

# Force database update
sudo -u hamdb bash -c "cd /opt/hamdb && HOME=/opt/hamdb /usr/local/bin/hamdb populate"
```

### Performance Optimization

#### For High-Traffic Usage
1. **Increase Connection Limits**:
   ```bash
   # Edit /etc/systemd/system/hamdb-gui.service
   LimitNOFILE=65536
   ```

2. **Database Indexing**:
   The database is pre-optimized with indexes on callsign, ZIP code, and name fields.

3. **Nginx Caching**:
   Consider enabling Nginx caching for static content in high-traffic scenarios.

### Log Analysis
```bash
# View application logs
sudo journalctl -u hamdb-gui -f

# View database update logs
tail -f /opt/hamdb/logs/update.log

# View Nginx access logs
sudo tail -f /var/log/nginx/access.log
```

## Security

### Security Features
- **Minimal Privileges** - Service runs as dedicated `hamdb` user
- **Database Security** - Unique passwords, limited permissions
- **Firewall Configuration** - UFW rules for ports 22, 80 only
- **Security Headers** - XSS protection, content type validation
- **Input Sanitization** - SQL injection prevention
- **Process Isolation** - Systemd security settings

### Security Recommendations
1. **Change Default Passwords** - Update database credentials after installation
2. **Regular Updates** - Keep system packages current
3. **Monitor Logs** - Review access logs regularly
4. **Network Security** - Use VPN for remote access
5. **Backup Encryption** - Encrypt configuration backups

## Updates and Maintenance

### Automatic Updates
- **FCC Database**: Updated daily at 2:30 AM via cron
- **Service Monitoring**: Automatic restart on failure
- **Log Rotation**: Automatic log management

### Manual Updates
```bash
# Update HamDB CLI
cd /tmp
wget https://raw.githubusercontent.com/k3ng/hamdb/main/hamdb
sudo cp hamdb /usr/local/bin/hamdb
sudo chmod +x /usr/local/bin/hamdb

# Update web interface (if new version available)
# Follow upgrade instructions for your specific version

# Update system packages
sudo apt update && sudo apt upgrade
```

### Backup Schedule
Recommended backup schedule:
- **Daily**: Automatic log rotation
- **Weekly**: Configuration backup via script
- **Monthly**: Full system backup including database

## Uninstallation

### Complete Removal
```bash
# Run the uninstall script
sudo /opt/hamdb/uninstall.sh

# Manually remove packages if desired
sudo apt remove nodejs mariadb-server nginx
sudo apt autoremove
```

### Partial Removal (Keep Dependencies)
The uninstall script removes HamDB GUI components but leaves system packages (Node.js, MariaDB, Nginx) installed for other applications.

## Contributing

### Reporting Issues
1. **Check Logs**: Include relevant logs from `journalctl -u hamdb-gui`
2. **System Info**: Provide OS version, hardware details
3. **Steps to Reproduce**: Clear description of the issue
4. **Expected vs Actual**: What should happen vs what actually happens

### Development Setup
```bash
# Clone repository
git clone https://github.com/your-repo/hamdb-gui-v1.git
cd hamdb-gui-v1

# Development installation
./hamdb_fixed_v2.1.sh

# Make changes to web interface
cd /opt/hamdb/web
# Edit files as needed

# Restart service to test changes
sudo systemctl restart hamdb-gui
```

### Pull Requests
1. Fork the repository
2. Create a feature branch
3. Test your changes thoroughly
4. Update documentation as needed
5. Submit pull request with clear description

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- **K3NG (Anthony Good)** - Creator of the original HamDB script and database tools
- **The Modern Ham KN4MKB (Billy D Penley) ** - for his setup blog post
- **FCC** - For providing public access to amateur radio license data
- **Amateur Radio Community** - For testing, feedback, and support

## Support

### Community Support
- **GitHub Issues**: Report bugs and request features
- **Amateur Radio Forums**: QRZ.com, eHam.net discussions
- **Social Media**: #HamRadio hashtags on Twitter

### Professional Support
For commercial deployments or custom installations, contact the maintainers.

## Related Projects

- **[K3NG HamDB](https://github.com/k3ng/hamdb)** - Original CLI database tool
- **[Modern Ham Blog Article] (https://themodernham.com/host-your-own-fcc-ham-radio-database-for-offline-use-with-hamdb/)
- **[HamLib](https://hamlib.github.io/)** - Ham radio control libraries
- **[WSJT-X](https://physics.princeton.edu/pulsar/k1jt/)** - Weak signal digital modes
- **[Fldigi](http://www.w1hkj.com/fldigi/)** - Digital mode software

## Changelog

### Version 1.0.0 (Current)
- Complete rewrite with modern web interface
- Enhanced security and authentication with fixed credentials
- Mobile-responsive design optimized for amateur radio operations
- Deployment with systemd service management
- Real-time monitoring and comprehensive health checks
- Automatic database updates with fallback mechanisms
- Comprehensive maintenance and troubleshooting tools
- Fixed all authentication, download, and import issues
- Production-ready installation with error handling and validation

---

**73!** 

*Built for the Amateur Radio Community*
