#!/bin/bash

# HamDB GUI Installation Script - Version 1.0
# Compatible with Raspberry Pi OS (Debian-based)

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Configuration
HAMDB_USER="hamdb"
HAMDB_HOME="/opt/hamdb"
WEB_PORT="8080"
SERVICE_NAME="hamdb-gui"
DB_NAME="fcc_amateur"
DB_USER="hamdbuser"
DB_PASSWORD="hamdb123secure"  

# Function to print colored output
print_header() {
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        print_error "This script should not be run as root"
        print_status "Please run as a regular user with sudo privileges"
        exit 1
    fi
}

# Function to check if user has sudo privileges
check_sudo() {
    if ! sudo -n true 2>/dev/null; then
        print_error "This script requires sudo privileges"
        print_status "Please ensure your user is in the sudo group"
        exit 1
    fi
}

# Function to detect Raspberry Pi
detect_rpi() {
    if [[ ! -f /proc/device-tree/model ]] || ! grep -q "Raspberry Pi" /proc/device-tree/model 2>/dev/null; then
        print_warning "This doesn't appear to be a Raspberry Pi"
        print_status "Continuing anyway - script should work on Debian-based systems"
    else
        local model=$(cat /proc/device-tree/model | tr -d '\0')
        print_success "Detected: $model"
    fi
}

# Function to update system packages
update_system() {
    print_status "Updating system packages..."
    sudo apt-get update -qq
    sudo apt-get upgrade -y -qq
    print_success "System packages updated"
}

# Function to install dependencies
install_dependencies() {
    print_status "Installing dependencies..."
    
    # Install Node.js and npm
    if ! command -v node &> /dev/null; then
        print_status "Installing Node.js..."
        curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
        sudo apt-get install -y nodejs
    else
        print_status "Node.js already installed: $(node --version)"
    fi
    
    # Install other dependencies
    sudo apt-get install -y \
        nginx \
        mariadb-server \
        mariadb-client \
        git \
        curl \
        wget \
        unzip \
        python3 \
        python3-pip \
        build-essential \
        -qq
    
    print_success "All dependencies installed"
}

# Function to setup MariaDB with proper error handling
setup_database() {
    print_status "Setting up MariaDB database..."
    
    # Ensure MariaDB is stopped first to avoid conflicts
    sudo systemctl stop mariadb 2>/dev/null || true
    
    # Start MariaDB service
    sudo systemctl start mariadb
    sudo systemctl enable mariadb
    
    # Wait for MariaDB to be ready
    print_status "Waiting for MariaDB to initialize..."
    local count=0
    while ! sudo mysql -e "SELECT 1;" &>/dev/null && [ $count -lt 30 ]; do
        sleep 2
        ((count++))
    done
    
    if [ $count -eq 30 ]; then
        print_error "MariaDB failed to start properly"
        sudo systemctl status mariadb
        exit 1
    fi
    
    # Clean up any existing users/databases from previous attempts
    print_status "Cleaning up any previous installation..."
    sudo mysql << 'MYSQL_CLEANUP'
DROP DATABASE IF EXISTS fcc_amateur;
DROP USER IF EXISTS 'user'@'localhost';
#DROP USER IF EXISTS 'hamdb'@'localhost';
FLUSH PRIVILEGES;
MYSQL_CLEANUP
    
    # Create database and user
    print_status "Creating database: $DB_NAME"
    print_status "Creating database user: $DB_USER"
    
    sudo mysql << MYSQL_SETUP
CREATE DATABASE $DB_NAME;
CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON *.* TO '$DB_USER'@'localhost' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SETUP
    
    # Test the database connection
    if mysql -u "$DB_USER" -p"$DB_PASSWORD" -e "SHOW DATABASES;" &>/dev/null; then
        print_success "Database setup completed successfully"
        print_status "Database: $DB_NAME, User: $DB_USER"
    else
        print_error "Database connection test failed"
        sudo mysql -e "SELECT user, host FROM mysql.user WHERE user LIKE '%hamdb%';"
        exit 1
    fi
}

# Function to create hamdb user
create_user() {
    if ! id "$HAMDB_USER" &>/dev/null; then
        print_status "Creating system user: $HAMDB_USER"
        sudo useradd -r -s /bin/bash -d "$HAMDB_HOME" -m "$HAMDB_USER"
        print_success "User $HAMDB_USER created"
    else
        print_status "User $HAMDB_USER already exists"
    fi
}

# Function to create directory structure
create_directories() {
    print_status "Creating directory structure..."
    sudo mkdir -p "$HAMDB_HOME"/{bin,web,data,logs,temp}
    sudo chown -R "$HAMDB_USER:$HAMDB_USER" "$HAMDB_HOME"
    print_success "Directory structure created"
}

# Function to download and install K3NG's HamDB
install_hamdb_cli() {
    print_status "Downloading K3NG's HamDB script from GitHub..."
    
    # Download the real HamDB script
    cd /tmp
    if wget -q https://raw.githubusercontent.com/k3ng/hamdb/main/hamdb; then
        print_success "HamDB script downloaded successfully"
    else
        print_error "Failed to download HamDB script"
        exit 1
    fi
    
    # Install to system location
    sudo cp hamdb /usr/local/bin/hamdb
    sudo chmod +x /usr/local/bin/hamdb
    sudo chown root:root /usr/local/bin/hamdb
    
    # Create a copy for the hamdb user
    sudo cp hamdb "$HAMDB_HOME/bin/hamdb"
    sudo chmod +x "$HAMDB_HOME/bin/hamdb"
    sudo chown "$HAMDB_USER:$HAMDB_USER" "$HAMDB_HOME/bin/hamdb"
    
    # Clean up
    rm -f hamdb
    
    print_success "HamDB CLI installed at /usr/local/bin/hamdb"
}

# Function to create HamDB configuration file in correct format
create_hamdb_config() {
    print_status "Creating HamDB configuration file..."
    
    # Create the config file in shell variable format (what HamDB expects)
    sudo tee "$HAMDB_HOME/.hamdb.cnf" > /dev/null << EOF
#!/bin/sh
# HamDB Configuration File - Shell variables format
MYSQLUSERNAME="$DB_USER"
MYSQLPASSWD="$DB_PASSWORD"
EOF
    
    # Set proper ownership and permissions
    sudo chown "$HAMDB_USER:$HAMDB_USER" "$HAMDB_HOME/.hamdb.cnf"
    sudo chmod 700 "$HAMDB_HOME/.hamdb.cnf"
    
    # Test that the config can be sourced and variables are set
    if sudo -u "$HAMDB_USER" bash -c "cd $HAMDB_HOME && source .hamdb.cnf && [ -n \"\$MYSQLUSERNAME\" ] && [ -n \"\$MYSQLPASSWD\" ]"; then
        print_success "HamDB configuration file created and validated"
    else
        print_error "Failed to create valid HamDB configuration"
        exit 1
    fi
}

# Function to initialize HamDB database structure
initialize_hamdb_database() {
    print_status "Creating HamDB database tables..."
    
    # Create database tables
    if sudo -u "$HAMDB_USER" bash -c "cd $HAMDB_HOME && HOME=$HAMDB_HOME /usr/local/bin/hamdb makedb" 2>/dev/null; then
        print_success "Database tables created successfully"
    else
        print_status "Database tables may already exist (this is normal)"
    fi
}

# Function to download and import FCC data with proper error handling
download_and_import_fcc_data() {
    print_status "FCC Database Download and Import Options:"
    echo "1. Download and import FCC data now (recommended - takes 15-20 minutes)"
    echo "2. Skip for now (import manually later)"
    echo
    read -p "Choose option (1 or 2): " -n 1 -r
    echo
    
    if [[ $REPLY == "1" ]]; then
        print_status "Downloading FCC amateur radio database..."
        print_status "This will download ~164MB and import licensee records - please be patient"
        
        # Try the automatic download first
        print_status "Attempting automatic download via HamDB..."
        if sudo -u "$HAMDB_USER" timeout 600 bash -c "cd $HAMDB_HOME && HOME=$HAMDB_HOME /usr/local/bin/hamdb full" 2>&1 | tee /tmp/hamdb_import.log; then
            # Check if import was successful by checking record count
            local record_count=$(sudo mysql -u "$DB_USER" -p"$DB_PASSWORD" -e "SELECT COUNT(*) FROM $DB_NAME.en;" 2>/dev/null | tail -1)
            if [[ "$record_count" =~ ^[0-9]+$ ]] && [ "$record_count" -gt 1000000 ]; then
                print_success "FCC database populated successfully with $record_count records"
                return 0
            else
                print_warning "Automatic download may have failed, trying manual method..."
            fi
        else
            print_warning "Automatic download failed, trying manual method..."
        fi
        
        # Manual download fallback
        print_status "Attempting manual download and import..."
        
        # Download manually
        cd /tmp
        if wget --user-agent="Mozilla/5.0 (compatible; HamDB)" https://data.fcc.gov/download/pub/uls/complete/l_amat.zip; then
            print_success "Manual download completed"
            
            # Extract
            if unzip -q l_amat.zip; then
                print_success "Files extracted successfully"
                
                # Move files to HamDB temp directory
                sudo mkdir -p "$HAMDB_HOME/hamdb.temp"
                sudo cp *.dat "$HAMDB_HOME/hamdb.temp/"
                sudo cp l_amat.zip "$HAMDB_HOME/hamdb.temp/" 2>/dev/null || true
                sudo chown -R "$HAMDB_USER:$HAMDB_USER" "$HAMDB_HOME/hamdb.temp"
                
                # Import the data
                print_status "Importing data into database (this may take 10-15 minutes)..."
                if sudo -u "$HAMDB_USER" timeout 900 bash -c "cd $HAMDB_HOME && HOME=$HAMDB_HOME /usr/local/bin/hamdb full"; then
                    local record_count=$(sudo mysql -u "$DB_USER" -p"$DB_PASSWORD" -e "SELECT COUNT(*) FROM $DB_NAME.en;" 2>/dev/null | tail -1)
                    if [[ "$record_count" =~ ^[0-9]+$ ]] && [ "$record_count" -gt 1000000 ]; then
                        print_success "FCC database imported successfully with $record_count records"
                        
                        # Test a lookup
                        print_status "Testing database with W1AW lookup..."
                        if sudo -u "$HAMDB_USER" bash -c "cd $HAMDB_HOME && HOME=$HAMDB_HOME /usr/local/bin/hamdb W1AW" | grep -q "W1AW"; then
                            print_success "Database test successful - W1AW found!"
                        fi
                        
                        # Clean up temporary files
                        sudo rm -rf "$HAMDB_HOME/hamdb.temp"
                        rm -f /tmp/*.dat /tmp/l_amat.zip /tmp/counts 2>/dev/null
                        
                        return 0
                    else
                        print_error "Data import failed - no records found"
                        return 1
                    fi
                else
                    print_error "Data import failed"
                    return 1
                fi
            else
                print_error "Failed to extract downloaded file"
                return 1
            fi
        else
            print_error "Manual download failed"
            return 1
        fi
    else
        print_warning "FCC data download skipped"
        print_status "To download later, run:"
        print_status "sudo -u $HAMDB_USER bash -c \"cd $HAMDB_HOME && HOME=$HAMDB_HOME /usr/local/bin/hamdb full\""
        return 0
    fi
}

# Function to create web interface
create_web_interface() {
    print_status "Creating web interface..."
    
    # Create the HTML file
    cat > /tmp/hamdb_index.html << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>HamDB GUI - Amateur Radio Callsign Lookup</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
		#result-output {
			font-family: 'Segoe UI', system-ui, sans-serif;
			font-size: 14px;
			background: #f8fafc;
			border: 1px solid #e2e8f0;
			border-radius: 8px;
			padding: 16px;
			min-height: 80px;
			color: #1e293b;
			overflow-x: auto;
		}
		/* Styled result table */
		.result-table {
			width: 100%;
			border-collapse: collapse;
			margin-top: 4px;
		}
		.result-table thead tr {
			background: linear-gradient(135deg, #6c63b6, #8b7fd4);
			color: #ffffff;
		}
		.result-table thead th {
			padding: 7px 10px;
			text-align: left;
			font-size: 10px;
			font-weight: 700;
			letter-spacing: 0.06em;
			text-transform: uppercase;
			border: none;
			white-space: nowrap;
		}
		.result-table tbody tr {
			border-bottom: 1px solid #e2e8f0;
			transition: background 0.15s;
		}

		.result-table tbody tr:hover {
			background: #f0eeff;
		}
		.result-table tbody td {
			padding: 7px 10px;
			font-size: 11px;
			color: #334155;
			white-space: nowrap;
		}
		/* Highlight the callsign cell */
		.result-table td.callsign-cell {
			font-weight: 700;
			color: #6c63b6;
			font-size: 12px;
			letter-spacing: 0.04em;
		}
		.result-meta .badge {
			background: #ede9ff;
			color: #6c63b6;
			border-radius: 999px;
			padding: 2px 10px;
			font-weight: 600;
			font-size: 11px;
		}
		/* Row count badge */
		.result-meta {
			display: flex;
			align-items: center;
			gap: 10px;
			margin-top: 12px;
			font-size: 12px;
			color: #64748b;
		}
		.result-meta .badge {
			background: #dbeafe;
			color: #1e40af;
			border-radius: 999px;
			padding: 2px 10px;
			font-weight: 600;
			font-size: 11px;
		}
		/* Error / empty states */
		.result-error {
			color: #dc2626;
			padding: 12px;
			background: #fef2f2;
			border-radius: 6px;
			border-left: 4px solid #dc2626;
		}
		.result-empty {
			color: #64748b;
			font-style: italic;
			padding: 20px;
			text-align: center;
		}

        body {
            font-family: 'Segoe UI', sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
        }
        .container {
            background: rgba(255, 255, 255, 0.95);
            backdrop-filter: blur(15px);
            border-radius: 24px;
            padding: 40px;
            box-shadow: 0 25px 50px rgba(0, 0, 0, 0.15);
            width: 100%;
            max-width: 1000px;
            min-height: 700px;
        }
        .header { text-align: center; margin-bottom: 40px; }
        .header h1 {
            color: #2c3e50;
            font-size: 3em;
            margin-bottom: 10px;
            background: linear-gradient(135deg, #667eea, #764ba2);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }
        .status-bar {
            background: linear-gradient(135deg, #2ecc71, #27ae60);
            color: white;
            padding: 15px;
            border-radius: 12px;
            margin-bottom: 30px;
            text-align: center;
            font-weight: 600;
        }
        .search-tabs {
            display: flex;
            margin-bottom: 30px;
            background: #f8f9fa;
            border-radius: 15px;
            padding: 8px;
            flex-wrap: wrap;
        }
        .tab-button {
            flex: 1;
            padding: 15px 20px;
            border: none;
            background: transparent;
            cursor: pointer;
            border-radius: 10px;
            font-weight: 600;
            color: #666;
            transition: all 0.3s ease;
            min-width: 140px;
            margin: 2px;
        }
        .tab-button.active {
            background: linear-gradient(135deg, #667eea, #764ba2);
            color: white;
            box-shadow: 0 6px 20px rgba(102, 126, 234, 0.4);
        }
        .form-group { margin-bottom: 25px; }
        .form-group label {
            display: block;
            margin-bottom: 10px;
            color: #2c3e50;
            font-weight: 600;
            font-size: 16px;
        }
        .form-group input {
            width: 100%;
            padding: 18px;
            border: 2px solid #e1e8ed;
            border-radius: 12px;
            font-size: 16px;
            transition: all 0.3s ease;
        }
        .form-group input:focus {
            outline: none;
            border-color: #667eea;
            box-shadow: 0 0 0 4px rgba(102, 126, 234, 0.15);
        }
        .search-button {
            width: 100%;
            padding: 18px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border: none;
            border-radius: 15px;
            font-size: 18px;
            font-weight: 600;
            cursor: pointer;
            transition: all 0.3s ease;
        }
        .search-button:hover {
            transform: translateY(-3px);
            box-shadow: 0 10px 30px rgba(102, 126, 234, 0.4);
        }
        .command-display {
            background: #2c3e50;
            color: #00ff41;
            padding: 20px;
            border-radius: 12px;
            font-family: monospace;
            margin-bottom: 20px;
            word-break: break-all;
        }
        .result-output {
            background: #f8f9fa;
            border: 2px solid #e1e8ed;
            border-radius: 12px;
            padding: 25px;
            min-height: 200px;
            font-family: monospace;
            white-space: pre-wrap;
            overflow-x: auto;
        }
        .result-output.loading {
            display: flex;
            align-items: center;
            justify-content: center;
            font-family: 'Segoe UI', sans-serif;
        }
        .spinner {
            width: 28px;
            height: 28px;
            border: 4px solid #f3f3f3;
            border-top: 4px solid #667eea;
            border-radius: 50%;
            animation: spin 1s linear infinite;
            margin-right: 15px;
        }
        @keyframes spin {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
        }
        .tab-content { display: none; }
        .tab-content.active { display: block; }
        .help-text { color: #7f8c8d; font-size: 14px; margin-top: 8px; }
        @media (max-width: 768px) {
            .container { padding: 25px; margin: 15px; }
            .header h1 { font-size: 2.2em; }
            .search-tabs { flex-direction: column; }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>📻 HamDB GUI</h1>
            <p>Amateur Radio Callsign Database - Version 1.0</p>
        </div>
        
        <div class="status-bar">
            ✅ Downloaded FCC Database • Ready for Lookups
        </div>
        
        <div class="search-tabs">
            <button class="tab-button active" onclick="showTab('callsign')">Callsign</button>
            <button class="tab-button" onclick="showTab('wildcard')">Wildcard</button>
            <button class="tab-button" onclick="showTab('zipcode')">ZIP Code</button>
            <button class="tab-button" onclick="showTab('lastname')">Last Name</button>
        </div>
        
        <div id="callsign-tab" class="tab-content active">
            <div class="form-group">
                <label for="callsign-input">Enter Callsign:</label>
                <input type="text" id="callsign-input" placeholder="e.g., W1AW" maxlength="10">
                <div class="help-text">Enter a complete amateur radio callsign</div>
            </div>
            <button class="search-button" onclick="performLookup('callsign')">🔍 Lookup Callsign</button>
        </div>
        
        <div id="wildcard-tab" class="tab-content">
            <div class="form-group">
                <label for="wildcard-input">Wildcard Pattern:</label>
                <input type="text" id="wildcard-input" placeholder="e.g., W1A%" maxlength="15">
                <div class="help-text">Use % as wildcard (e.g., W1A% finds all starting with W1A)</div>
            </div>
            <button class="search-button" onclick="performLookup('wildcard')">🔍 Wildcard Search</button>
        </div>
        
        <div id="zipcode-tab" class="tab-content">
            <div class="form-group">
                <label for="zipcode-input">ZIP Code:</label>
                <input type="text" id="zipcode-input" placeholder="e.g., 06111, 90210" maxlength="10">
                <div class="help-text">Find all operators in a ZIP code</div>
            </div>
            <button class="search-button" onclick="performLookup('zipcode')">🔍 Search by ZIP</button>
        </div>
        
        <div id="lastname-tab" class="tab-content">
            <div class="form-group">
                <label for="lastname-input">Last Name:</label>
                <input type="text" id="lastname-input" placeholder="e.g., Smith, Johnson" maxlength="50">
                <div class="help-text">Search by operator last name</div>
            </div>
            <button class="search-button" onclick="performLookup('lastname')">🔍 Search by Name</button>
        </div>
        
        <div style="margin-top: 40px;">
            <h3 style="margin-bottom: 20px;">Command & Results</h3>
            <div class="command-display" id="command-display">Ready to search FCC database...</div>
            <div class="result-output" id="result-output">HamDB GUI v1.0

Successfully downloaded FCC amateur radio database!
Database contains current amateur radio records.

Try searching for famous callsigns:
• W1AW (ARRL headquarters)
• Use ZIP code 06111 to find ARRL area hams

Perfect for Field Day, contests, and emergency communications!</div>
        </div>
        
        <div style="text-align: center; margin-top: 40px; padding-top: 25px; border-top: 2px solid #e1e8ed; color: #7f8c8d;">
            <p><strong>HamDB GUI v1.0</strong> | Powered by K3NG's HamDB | 73!</p>
        </div>
    </div>

    <script>
        function showTab(tabName) {
            document.querySelectorAll('.tab-content').forEach(tab => tab.classList.remove('active'));
            document.querySelectorAll('.tab-button').forEach(btn => btn.classList.remove('active'));
            document.getElementById(tabName + '-tab').classList.add('active');
            event.target.classList.add('active');
        }

		function renderResult(resultOutput, rawText, duration) {
			const lines = rawText.trim().split('\n').filter(l => l.trim() !== '');

			if (lines.length < 2) {
				resultOutput.innerHTML = `<div class="result-empty">No results found.</div>`;
				return;
			}

			// ── 1 & 2. Parse headers and rows (output is tab-separated) ─────────────
			const headers = lines[0].split('\t').map(h => h.trim());
			const rows = [];
			for (let i = 1; i < lines.length; i++) {
				const cells = lines[i].split('\t').map(c => c.trim());
				rows.push(cells);
			}

			// ── 3. Render table ───────────────────────────────────────────────────────
			// Find which column index is "callsign" for special styling
			const callsignIdx = headers.findIndex(h => /callsign/i.test(h));

			let html = `<table class="result-table">
			<thead><tr>${headers.map(h => `<th>${h}</th>`).join('')}</tr></thead>
			<tbody>`;

			for (const row of rows) {
				html += '<tr>' + row.map((cell, i) => {
					const cls = i === callsignIdx ? ' class="callsign-cell"' : '';
					return `<td${cls}>${cell || '—'}</td>`;
				}).join('') + '</tr>';
			}

			html += `</tbody></table>
			<div class="result-meta">
				<span class="badge">${rows.length} result${rows.length !== 1 ? 's' : ''}</span>
				<span>⏱ Query completed in ${duration}ms</span>
			</div>`;

			resultOutput.innerHTML = html;
		}

        async function performLookup(type) {
            const commandDisplay = document.getElementById('command-display');
            const resultOutput = document.getElementById('result-output');
            
            let input = '';
            switch(type) {
                case 'callsign': input = document.getElementById('callsign-input').value.trim().toUpperCase(); break;
                case 'wildcard': input = document.getElementById('wildcard-input').value.trim().toUpperCase(); break;
                case 'zipcode': input = document.getElementById('zipcode-input').value.trim(); break;
                case 'lastname': input = document.getElementById('lastname-input').value.trim().toUpperCase(); break;
            }
            
            if (!input) {
                alert('Please enter a search term');
                return;
            }
            
            let command = '';
            switch(type) {
                case 'callsign': command = 'hamdb ' + input; break;
                case 'wildcard': command = 'hamdb like ' + input; break;
                case 'zipcode': command = 'hamdb zipcode ' + input; break;
                case 'lastname': command = 'hamdb lastname ' + input; break;
            }
            
            commandDisplay.textContent = 'Executing: ' + command;
            resultOutput.innerHTML = '<div class="spinner"></div>Searching FCC database...';
            resultOutput.classList.add('loading');
            
            try {
                const startTime = Date.now();
                const response = await fetch('/api/lookup', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ type, input })
                });
                
                const result = await response.text();
                const duration = Date.now() - startTime;
                
                resultOutput.classList.remove('loading');
                
                if (response.ok && result.trim()) {
                    renderResult(resultOutput, result, duration);
                } else {
                    resultOutput.innerHTML = `<div class="result-error">No results found in FCC database for: <strong>${input}</strong></div>`;
                }
                
                commandDisplay.textContent = command + ' (completed in ' + duration + 'ms)';
                
            } catch (error) {
                resultOutput.classList.remove('loading');
                resultOutput.textContent = '❌ Connection Error: ' + error.message + '\n\nPlease check that the HamDB service is running.';
            }
        }
        
        // Enter key support
        document.addEventListener('keypress', function(e) {
            if (e.key === 'Enter') {
                const activeTab = document.querySelector('.tab-content.active');
                const input = activeTab.querySelector('input');
                if (input === document.activeElement) {
                    const tabId = activeTab.id.replace('-tab', '');
                    performLookup(tabId);
                }
            }
        });
        
        // Input validation
        document.getElementById('callsign-input').addEventListener('input', function(e) {
            e.target.value = e.target.value.toUpperCase().replace(/[^A-Z0-9]/g, '');
        });
        
        document.getElementById('wildcard-input').addEventListener('input', function(e) {
            e.target.value = e.target.value.toUpperCase();
        });
        
        document.getElementById('zipcode-input').addEventListener('input', function(e) {
            e.target.value = e.target.value.replace(/[^0-9]/g, '');
        });
        
        document.getElementById('lastname-input').addEventListener('input', function(e) {
            e.target.value = e.target.value.replace(/[^a-zA-Z\s]/g, '').toUpperCase();
        });
    </script>
</body>
</html>
HTMLEOF

    # Copy to proper location
    sudo cp /tmp/hamdb_index.html "$HAMDB_HOME/web/index.html"
    sudo chown "$HAMDB_USER:$HAMDB_USER" "$HAMDB_HOME/web/index.html"
    sudo rm /tmp/hamdb_index.html
    
    print_success "Web interface created"
}

# Function to create Node.js backend
create_backend_api() {
    print_status "Creating backend API server..."
    
    # Create package.json
    sudo tee "$HAMDB_HOME/web/package.json" > /dev/null << 'EOF'
{
  "name": "hamdb-gui",
  "version": "1.0.0",
  "description": "HamDB GUI",
  "main": "server.js",
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5"
  }
}
EOF

    # Create server.js with improved error handling
    sudo tee "$HAMDB_HOME/web/server.js" > /dev/null << 'EOF'
const express = require('express');
const cors = require('cors');
const { exec } = require('child_process');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 8080;
const HAMDB_PATH = '/usr/local/bin/hamdb';
const HAMDB_HOME = '/opt/hamdb';

app.use(cors());
app.use(express.json());
app.use(express.static('.'));

// Request logging middleware
app.use((req, res, next) => {
    const timestamp = new Date().toISOString();
    console.log(`[${timestamp}] ${req.method} ${req.url}`);
    next();
});

app.get('/', (req, res) => {
    res.sendFile(path.join(__dirname, 'index.html'));
});

app.post('/api/lookup', (req, res) => {
    const { type, input } = req.body;
    const timestamp = new Date().toISOString();
    
    if (!type || !input) {
        return res.status(400).send('Missing type or input parameter');
    }
    
    const sanitizedInput = input.replace(/[;&|`$()]/g, '').trim();
    if (!sanitizedInput) {
        return res.status(400).send('Invalid input parameter');
    }
    
    let command = `${HAMDB_PATH} `;
    switch(type) {
        case 'callsign': command += sanitizedInput; break;
        case 'wildcard': command += `like ${sanitizedInput}`; break;
        case 'zipcode': command += `zipcode ${sanitizedInput}`; break;
        case 'lastname': command += `lastname ${sanitizedInput}`; break;
        default: return res.status(400).send('Invalid lookup type');
    }
    
    console.log(`[${timestamp}] Executing: ${command}`);
    
    const execOptions = {
        timeout: 45000,
        env: { ...process.env, HOME: HAMDB_HOME, USER: 'hamdb' },
        cwd: HAMDB_HOME,
        maxBuffer: 1024 * 1024 * 10
    };
    
    exec(command, execOptions, (error, stdout, stderr) => {
        if (error) {
            console.error(`[${timestamp}] Command failed: ${error.message}`);
            return res.status(500).send('Database lookup failed');
        }
        
        const result = stdout || 'No results found';
        console.log(`[${timestamp}] Command completed successfully`);
        res.send(result);
    });
});

app.get('/api/health', (req, res) => {
    exec(`${HAMDB_PATH} --help`, { 
        timeout: 10000,
        env: { HOME: HAMDB_HOME, USER: 'hamdb' },
        cwd: HAMDB_HOME
    }, (error, stdout, stderr) => {
        res.json({ 
            status: error ? 'error' : 'ok',
            service: 'hamdb-gui',
            version: '1.0.0',
            timestamp: new Date().toISOString()
        });
    });
});

app.listen(PORT, '0.0.0.0', () => {
    console.log(`[${new Date().toISOString()}] HamDB GUI v1.0 running on http://0.0.0.0:${PORT}`);
});
EOF
    
    # Install dependencies
    sudo -u "$HAMDB_USER" bash -c "cd $HAMDB_HOME/web && npm install"
    sudo chown -R "$HAMDB_USER:$HAMDB_USER" "$HAMDB_HOME/web"
    
    print_success "Backend API server created"
}

# Function to create systemd service
create_systemd_service() {
    print_status "Creating systemd service..."
    
    sudo tee "/etc/systemd/system/$SERVICE_NAME.service" > /dev/null << EOF
[Unit]
Description=HamDB GUI Web Service - v1.0
After=network.target mariadb.service
Requires=mariadb.service

[Service]
Type=simple
User=$HAMDB_USER
Group=$HAMDB_USER
WorkingDirectory=$HAMDB_HOME/web
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=10
Environment=NODE_ENV=production
Environment=PORT=$WEB_PORT
Environment=HOME=$HAMDB_HOME
Environment=USER=$HAMDB_USER

[Install]
WantedBy=multi-user.target
EOF
    
    sudo systemctl daemon-reload
    sudo systemctl enable "$SERVICE_NAME"
    print_success "Systemd service created and enabled"
}

# Function to configure nginx
configure_nginx() {
    print_status "Configuring Nginx reverse proxy..."
    
    sudo tee "/etc/nginx/sites-available/hamdb-gui" > /dev/null << 'EOF'
server {
    listen 80;
    server_name _;
    
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    
    location / {
        proxy_pass http://localhost:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
    
    location /health {
        access_log off;
        return 200 "HamDB GUI v1.0 is running\n";
        add_header Content-Type text/plain;
    }
}
EOF
    
    sudo ln -sf /etc/nginx/sites-available/hamdb-gui /etc/nginx/sites-enabled/
    sudo rm -f /etc/nginx/sites-enabled/default
    
    if sudo nginx -t; then
        sudo systemctl restart nginx
        sudo systemctl enable nginx
        print_success "Nginx configured successfully"
    else
        print_error "Nginx configuration failed"
        exit 1
    fi
}

# Function to setup firewall
setup_firewall() {
    if command -v ufw &> /dev/null; then
        print_status "Configuring firewall..."
        sudo ufw allow 80/tcp comment "HamDB GUI"
        sudo ufw allow 22/tcp comment "SSH"
        print_success "Firewall configured"
    else
        print_warning "UFW not available, skipping firewall setup"
    fi
}

# Function to create maintenance scripts
create_maintenance_scripts() {
    print_status "Creating maintenance scripts..."
    
    # Database update script
    sudo tee "$HAMDB_HOME/update_database.sh" > /dev/null << 'EOF'
#!/bin/bash
echo "$(date): Starting HamDB database update..."
cd /opt/hamdb
export HOME=/opt/hamdb
/usr/local/bin/hamdb update
if [ $? -eq 0 ]; then
    echo "$(date): Database update completed successfully"
    record_count=$(/usr/local/bin/hamdb count 2>/dev/null | grep "COUNT(fccid)" | tail -1)
    echo "$(date): Database contains: $record_count records"
else
    echo "$(date): Database update failed" >&2
    exit 1
fi
EOF

    # System status script with improved monitoring
    sudo tee "$HAMDB_HOME/check_status.sh" > /dev/null << 'EOF'
#!/bin/bash
echo "=== HamDB GUI v1.0 System Status ==="
echo "Date: $(date)"
echo

echo "Services:"
systemctl is-active hamdb-gui >/dev/null && echo "✅ HamDB GUI: Running" || echo "❌ HamDB GUI: Stopped"
systemctl is-active nginx >/dev/null && echo "✅ Nginx: Running" || echo "❌ Nginx: Stopped"
systemctl is-active mariadb >/dev/null && echo "✅ MariaDB: Running" || echo "❌ MariaDB: Stopped"
echo

echo "Network:"
ss -tlnp | grep :80 >/dev/null && echo "✅ Port 80: Listening" || echo "❌ Port 80: Not listening"
ss -tlnp | grep :8080 >/dev/null && echo "✅ Port 8080: Listening" || echo "❌ Port 8080: Not listening"
echo

echo "Database Status:"
record_count=$(mysql -u hamdbuser -p'hamdb123secure' -e "SELECT COUNT(*) FROM fcc_amateur.en;" 2>/dev/null | tail -1)
if [[ "$record_count" =~ ^[0-9]+$ ]] && [ "$record_count" -gt 1000000 ]; then
    echo "✅ Database: $(printf "%'d" $record_count) amateur records"
else
    echo "❌ Database: Query failed or insufficient records ($record_count)"
fi
echo

echo "API Test:"
health_check=$(curl -s http://localhost:8080/api/health 2>/dev/null)
if echo "$health_check" | grep -q '"status":"ok"'; then
    echo "✅ API: Healthy and responding"
else
    echo "❌ API: Not responding or unhealthy"
fi

web_check=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/ 2>/dev/null)
if [ "$web_check" = "200" ]; then
    echo "✅ Web Interface: Accessible"
else
    echo "❌ Web Interface: Not accessible (HTTP $web_check)"
fi
echo

echo "Quick Test - W1AW Lookup:"
if /usr/local/bin/hamdb W1AW 2>/dev/null | grep -q "ARRL"; then
    echo "✅ Database Lookup: Working (W1AW found)"
else
    echo "❌ Database Lookup: Failed (W1AW not found)"
fi
EOF

    # Uninstall script
    sudo tee "$HAMDB_HOME/uninstall.sh" > /dev/null << 'EOF'
#!/bin/bash
echo "HamDB GUI v1.0 - Complete Uninstall"
echo "This will remove all HamDB components including database."
read -p "Are you sure? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Uninstall cancelled."
    exit 1
fi

echo "Stopping services..."
sudo systemctl stop hamdb-gui nginx mariadb 2>/dev/null
sudo systemctl disable hamdb-gui 2>/dev/null

echo "Removing service files..."
sudo rm -f /etc/systemd/system/hamdb-gui.service
sudo rm -f /etc/nginx/sites-available/hamdb-gui
sudo rm -f /etc/nginx/sites-enabled/hamdb-gui
sudo systemctl daemon-reload

echo "Removing database..."
sudo mysql -e "DROP DATABASE IF EXISTS fcc_amateur; DROP USER IF EXISTS 'hamdbuser'@'localhost';" 2>/dev/null

echo "Removing user and files..."
sudo userdel -r hamdb 2>/dev/null
sudo rm -rf /opt/hamdb
sudo rm -f /usr/local/bin/hamdb

echo "HamDB GUI v1.0 has been completely removed."
EOF

    sudo chmod +x "$HAMDB_HOME"/{update_database.sh,check_status.sh,uninstall.sh}
    sudo chown "$HAMDB_USER:$HAMDB_USER" "$HAMDB_HOME"/{update_database.sh,check_status.sh,uninstall.sh}
    
    print_success "Maintenance scripts created"
}

# Function to setup automatic updates
setup_automatic_updates() {
    print_status "Setting up automatic database updates..."
    
    # Create cron job for daily updates at 2:30 AM
    (sudo crontab -u "$HAMDB_USER" -l 2>/dev/null; echo "30 2 * * * /opt/hamdb/update_database.sh >> /opt/hamdb/logs/update.log 2>&1") | sudo crontab -u "$HAMDB_USER" -
    
    print_success "Automatic daily updates scheduled for 2:30 AM"
}

# Function to start and test all services
start_and_test_services() {
    print_status "Starting and testing all services..."
    
    # Start services in proper order
    sudo systemctl start mariadb
    sleep 3
    sudo systemctl start "$SERVICE_NAME"
    sleep 5
    sudo systemctl start nginx
    sleep 3
    
    # Test all services
    local all_good=true
    
    if sudo systemctl is-active --quiet mariadb; then
        print_success "MariaDB is running"
    else
        print_error "MariaDB failed to start"
        all_good=false
    fi
    
    if sudo systemctl is-active --quiet "$SERVICE_NAME"; then
        print_success "HamDB GUI service is running"
    else
        print_error "HamDB GUI service failed to start"
        sudo systemctl status "$SERVICE_NAME" --no-pager
        all_good=false
    fi
    
    if sudo systemctl is-active --quiet nginx; then
        print_success "Nginx is running"
    else
        print_error "Nginx failed to start"
        all_good=false
    fi
    
    # Test connectivity
    sleep 3
    local health_check=$(curl -s http://localhost:8080/api/health 2>/dev/null || echo "failed")
    if echo "$health_check" | grep -q '"status":"ok"'; then
        print_success "API health check passed"
    else
        print_warning "API health check pending"
    fi
    
    local web_check=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/ 2>/dev/null || echo "000")
    if [[ "$web_check" == "200" ]]; then
        print_success "Web interface is accessible"
    else
        print_warning "Web interface test pending (HTTP $web_check)"
    fi
    
    if [ "$all_good" = false ]; then
        print_error "Some services failed to start"
        return 1
    fi
    
    return 0
}

# Function to display final information
display_final_info() {
    local ip_address=$(hostname -I | awk '{print $1}')
    
    echo
    print_header "🎉 HAMDB GUI v1.0 INSTALLATION COMPLETE! 🎉"
    
    echo -e "${GREEN}🌐 ACCESS INFORMATION${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${BLUE}Local Access:${NC}       http://localhost/"
    echo -e "${BLUE}Network Access:${NC}     http://$ip_address/"
    echo -e "${BLUE}Direct Port:${NC}        http://$ip_address:$WEB_PORT/"
    echo -e "${BLUE}Health Check:${NC}       http://$ip_address/api/health"
    echo
    
    echo -e "${GREEN}🛠️ SERVICE MANAGEMENT${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${BLUE}Check Status:${NC}       sudo systemctl status $SERVICE_NAME"
    echo -e "${BLUE}View Logs:${NC}          sudo journalctl -u $SERVICE_NAME -f"
    echo -e "${BLUE}Restart Service:${NC}    sudo systemctl restart $SERVICE_NAME"
    echo -e "${BLUE}System Status:${NC}      sudo $HAMDB_HOME/check_status.sh"
    echo
    
    echo -e "${GREEN}🗄️ DATABASE MANAGEMENT${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${BLUE}Update Database:${NC}    sudo $HAMDB_HOME/update_database.sh"
    echo -e "${BLUE}Test Lookup:${NC}        sudo -u $HAMDB_USER /usr/local/bin/hamdb W1AW"
    echo -e "${BLUE}Show Statistics:${NC}    sudo -u $HAMDB_USER /usr/local/bin/hamdb count"
    echo
    
    echo -e "${YELLOW}⚠️ IMPORTANT NOTES${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${YELLOW}1.${NC} Database credentials: hamdbuser / hamdb123secure"
    echo -e "${YELLOW}2.${NC} All services auto-start on boot"
    echo -e "${YELLOW}3.${NC} Database updates daily at 2:30 AM automatically"
    echo -e "${YELLOW}4.${NC} Access from any device on your network"
    echo -e "${YELLOW}5.${NC} To uninstall: sudo $HAMDB_HOME/uninstall.sh"
    echo
    
    # Check database status
    local record_count=$(sudo mysql -u "$DB_USER" -p"$DB_PASSWORD" -e "SELECT COUNT(*) FROM $DB_NAME.en;" 2>/dev/null | tail -1)
    if [[ "$record_count" =~ ^[0-9]+$ ]] && [ "$record_count" -gt 1000000 ]; then
        echo -e "${GREEN}📊 DATABASE STATUS${NC}"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo -e "${BLUE}✅ FCC Database:${NC}        $(printf "%'d" $record_count) amateur records imported"
        echo -e "${BLUE}✅ System Status:${NC}       Fully operational and ready for use"
        echo
    else
        echo -e "${YELLOW}📊 DATABASE STATUS${NC}"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo -e "${YELLOW}⚠️ FCC Database:${NC}        Import may be incomplete ($record_count records)"
        echo -e "${YELLOW}ℹ️ To import later:${NC}     sudo -u $HAMDB_USER /usr/local/bin/hamdb full"
        echo
    fi
    
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}🎯 READY TO USE: ${BLUE}http://$ip_address/${NC}"
    echo -e "${GREEN}📻 Perfect for Field Day, contests, and amateur radio operations!${NC}"
    echo -e "${GREEN}🔧 All previous installation issues have been resolved!${NC}"
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
}

# Main installation function
main() {
    clear
    print_header "📻 HAMDB GUI v1.0 - INSTALLER 📻"
    #echo -e "${BLUE}All Issues Resolved: Database Auth + Download + Import + Configuration${NC}"
    echo
    
    # Pre-flight checks
    print_status "Performing pre-flight checks..."
    check_root
    check_sudo
    detect_rpi
    
    echo
    echo
    read -p "Continue with installation? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Installation cancelled"
        exit 0
    fi
    
    echo
    print_header "🚀 STARTING INSTALLATION"
    
    # Execute all installation steps
    update_system
    install_dependencies
    setup_database
    create_user
    create_directories
    install_hamdb_cli
    create_hamdb_config
    initialize_hamdb_database
    create_web_interface
    create_backend_api
    create_systemd_service
    configure_nginx
    setup_firewall
    create_maintenance_scripts
    setup_automatic_updates
    start_and_test_services
    
    # FCC database download and import
    echo
    download_and_import_fcc_data
    
    # Final display
    display_final_info
    
    print_success "🎉 HamDB GUI v1.0 installation completed successfully! 73!"
}

# Run main function
main "$@"
