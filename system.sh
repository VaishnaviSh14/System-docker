
#!/bin/bash

# ========================================================
# system-doctor.sh - Smart System Cleanup & Health Script
# ========================================================

# Set script to exit on error
set -e

# Set color variables for better output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
NC='\033[0m' # No Color

# Constants
LOG_FILE="$HOME/system-doctor-$(date +%Y-%m-%d).log"
BACKUP_DIR="$HOME/system-doctor-backup-$(date +%Y-%m-%d)"
CRITICAL_DIRS=("/etc" "$HOME/.ssh" "$HOME/.config")
MIN_SPACE_ALERT=10 # Alert when less than 10% disk space available
HIGH_CPU_THRESHOLD=80 # CPU usage percentage to trigger alert
HIGH_MEM_THRESHOLD=80 # Memory usage percentage to trigger alert

# Email configuration
SEND_EMAIL=false
EMAIL_RECIPIENT=""
EMAIL_SUBJECT="System Doctor Report - $(hostname) - $(date +%Y-%m-%d)"
EMAIL_REPORT_FILE="/tmp/system-doctor-report-$(date +%Y-%m-%d).txt"

# Function to log messages
log_message() {
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo -e "${timestamp} - $1" | tee -a "$LOG_FILE"
}

# Function to display section headers
header() {
    echo -e "\n${BLUE}==== $1 ====${NC}"
    log_message "SECTION: $1"
    
    # Also write to email report if enabled
    if [ "$SEND_EMAIL" = true ]; then
        echo -e "\n==== $1 ====" >> "$EMAIL_REPORT_FILE"
    fi
}

# Function to display success messages
success() {
    echo -e "${GREEN}✓ $1${NC}"
    log_message "SUCCESS: $1"
    
    # Also write to email report if enabled
    if [ "$SEND_EMAIL" = true ]; then
        echo -e "SUCCESS: $1" >> "$EMAIL_REPORT_FILE"
    fi
}

# Function to display warning messages
warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
    log_message "WARNING: $1"
    
    # Also write to email report if enabled
    if [ "$SEND_EMAIL" = true ]; then
        echo -e "WARNING: $1" >> "$EMAIL_REPORT_FILE"
    fi
}

# Function to display error messages
error() {
    echo -e "${RED}✗ $1${NC}"
    log_message "ERROR: $1"
    
    # Also write to email report if enabled
    if [ "$SEND_EMAIL" = true ]; then
        echo -e "ERROR: $1" >> "$EMAIL_REPORT_FILE"
    fi
}

# Function to check if running as root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        warning "Not running as root. Some cleaning operations may fail."
        log_message "Script running without root privileges"
    else
        success "Running with root privileges"
    fi
}

# Function to setup email reporting
setup_email() {
    header "Email Notification Setup"
    
    # Check if mail command is available
    if ! command -v mail &> /dev/null; then
        warning "Mail command not found. Email notifications will not be sent."
        warning "Install mailutils package to enable email notifications."
        SEND_EMAIL=false
        return
    fi
    
    # Ask for email recipient
    read -p "Do you want to receive email notifications? (y/n): " email_confirm
    if [[ $email_confirm == [yY] ]]; then
        read -p "Enter email address to send reports to: " EMAIL_RECIPIENT
        
        if [[ -z "$EMAIL_RECIPIENT" ]]; then
            warning "No email address provided. Email notifications will not be sent."
            SEND_EMAIL=false
        else
            SEND_EMAIL=true
            success "Email notifications will be sent to: $EMAIL_RECIPIENT"
            
            # Initialize report file
            echo "System Doctor Report - $(hostname)" > "$EMAIL_REPORT_FILE"
            echo "Generated on: $(date)" >> "$EMAIL_REPORT_FILE"
            echo "=======================================" >> "$EMAIL_REPORT_FILE"
        fi
    else
        SEND_EMAIL=false
    fi
}

# Function to create backup of critical directories
create_backup() {
    header "Creating Backup of Critical Files"
    
    # Create backup directory if it doesn't exist
    if [ ! -d "$BACKUP_DIR" ]; then
        mkdir -p "$BACKUP_DIR"
        success "Created backup directory at $BACKUP_DIR"
    fi
    
    # Backup each critical directory
    for dir in "${CRITICAL_DIRS[@]}"; do
        if [ -d "$dir" ]; then
            echo -e "Backing up ${YELLOW}$dir${NC}..."
            backup_name=$(echo "$dir" | sed 's/\//-/g' | sed 's/^-//')
            rsync -a --exclude=".*cache*" "$dir" "$BACKUP_DIR/$backup_name" 2>/dev/null || warning "Could not fully backup $dir"
            success "Backed up $dir"
        else
            warning "Directory $dir does not exist, skipping backup"
        fi
    done
    
    success "Backup completed at $BACKUP_DIR"
}

# Function to clean temporary files
clean_temp_files() {
    header "Cleaning Temporary Files"
    
    # Clean /tmp directory (exclude files in use and created today)
    echo -e "Cleaning ${YELLOW}/tmp${NC} directory..."
    find /tmp -type f -atime +1 -not -name ".*" -delete 2>/dev/null || warning "Could not clean all files in /tmp"
    success "Cleaned old files in /tmp"
    
    # Clean user cache directories
    echo -e "Cleaning ${YELLOW}browser caches${NC}..."
    
    # Firefox cache
    if [ -d "$HOME/.mozilla/firefox" ]; then
        find "$HOME/.mozilla/firefox" -name "*.sqlite" -exec sqlite3 {} 'VACUUM;' \; 2>/dev/null
        find "$HOME/.mozilla/firefox" -name "cache*" -type d -exec rm -rf {} \; 2>/dev/null || true
        success "Cleaned Firefox cache"
    fi
    
    # Chrome/Chromium cache
    for browser_cache in "$HOME/.cache/google-chrome" "$HOME/.cache/chromium"; do
        if [ -d "$browser_cache" ]; then
            rm -rf "${browser_cache}/Default/Cache/"* 2>/dev/null || true
            rm -rf "${browser_cache}/Default/Code Cache/"* 2>/dev/null || true
            success "Cleaned $(basename "$browser_cache") cache"
        fi
    done
    
    # Clean thumbnails
    echo -e "Cleaning ${YELLOW}thumbnail cache${NC}..."
    if [ -d "$HOME/.cache/thumbnails" ]; then
        rm -rf "$HOME/.cache/thumbnails/"* 2>/dev/null || warning "Could not clean all thumbnails"
        success "Cleaned thumbnail cache"
    fi
}

# Function to analyze disk usage
analyze_disk_usage() {
    header "Analyzing Disk Usage"
    
    # Show filesystem usage
    echo -e "${YELLOW}Filesystem Usage:${NC}"
    df_output=$(df -h | grep -v "tmpfs" | grep -v "udev")
    echo "$df_output"
    log_message "Filesystem usage: $(echo "$df_output" | tr '\n' ' ')"
    
    # Also write to email report if enabled
    if [ "$SEND_EMAIL" = true ]; then
        echo -e "\nFilesystem Usage:" >> "$EMAIL_REPORT_FILE"
        df -h | grep -v "tmpfs" | grep -v "udev" >> "$EMAIL_REPORT_FILE"
    fi
    
    # Check if any partition is running low on space
    low_space=$(df | grep -v "tmpfs" | awk '{print $5}' | grep -v "Use%" | sed 's/%//g' | awk '$1 > 90 {print}')
    if [ ! -z "$low_space" ]; then
        warning "Low disk space detected on one or more partitions!"
        df -h | grep -v "tmpfs" | head -n 1
        low_space_details=$(df -h | grep -v "tmpfs" | grep -v "Use" | awk '{gsub(/%/,"",$5); if($5 > 90) print $0}')
        echo "$low_space_details"
        
        # Also write to email report if enabled
        if [ "$SEND_EMAIL" = true ]; then
            echo -e "\nWARNING: Low disk space detected!" >> "$EMAIL_REPORT_FILE"
            echo "$low_space_details" >> "$EMAIL_REPORT_FILE"
        fi
    fi
    
    # Find largest directories in home
    echo -e "\n${YELLOW}Largest directories in $HOME:${NC}"
    large_dirs=$(du -sh "$HOME"/* 2>/dev/null | sort -rh | head -n 10)
    echo "$large_dirs"
    
    # Also write to email report if enabled
    if [ "$SEND_EMAIL" = true ]; then
        echo -e "\nLargest directories in $HOME:" >> "$EMAIL_REPORT_FILE"
        echo "$large_dirs" >> "$EMAIL_REPORT_FILE"
    fi
    
    # Find largest files over 100MB
    echo -e "\n${YELLOW}Largest files (>100MB):${NC}"
    large_files=$(find "$HOME" -type f -size +100M -exec ls -lh {} \; 2>/dev/null | sort -k 5 -rh | head -n 10 | awk '{print $5 " " $9}')
    echo "$large_files"
    
    # Also write to email report if enabled
    if [ "$SEND_EMAIL" = true ]; then
        echo -e "\nLargest files (>100MB):" >> "$EMAIL_REPORT_FILE"
        echo "$large_files" >> "$EMAIL_REPORT_FILE"
    fi
    
    # Check for old log files
    echo -e "\n${YELLOW}Old log files that might be cleared:${NC}"
    old_logs=$(find /var/log -type f -name "*.log.*" -o -name "*.gz" -o -name "*.old" 2>/dev/null | head -n 10)
    echo "$old_logs"
    
    # Also write to email report if enabled
    if [ "$SEND_EMAIL" = true ]; then
        echo -e "\nOld log files that might be cleared:" >> "$EMAIL_REPORT_FILE"
        echo "$old_logs" >> "$EMAIL_REPORT_FILE"
    fi
}

# Function to analyze system resources
analyze_system_resources() {
    header "Analyzing System Resources"
    
    # Show memory usage for Linux
    if command -v free >/dev/null 2>&1; then
        mem_output=$(free -h)
        mem_usage=$(free | grep Mem | awk '{print int($3/$2 * 100.0)}')
    else
        # For macOS, use vm_stat
        mem_output=$(vm_stat)
        free_pages=$(echo "$mem_output" | grep "free" | awk '{print $3}' | sed 's/\.//')
        page_size=$(sysctl -n hw.pagesize)
        free_memory=$(($free_pages * $page_size / 1024 / 1024))
        total_memory=$(sysctl -n hw.memsize)
        total_memory_mb=$(($total_memory / 1024 / 1024))
        mem_usage=$(($free_memory * 100 / $total_memory_mb))
        mem_output="Total Memory: $total_memory_mb MB\nFree Memory: $free_memory MB"
    fi

    echo "$mem_output"
    log_message "Memory usage: ${mem_usage}%"
    
    # Also write to email report if enabled
    if [ "$SEND_EMAIL" = true ]; then
        echo -e "\nMemory Usage:" >> "$EMAIL_REPORT_FILE"
        echo "$mem_output" >> "$EMAIL_REPORT_FILE"
        echo "Memory usage: ${mem_usage}%" >> "$EMAIL_REPORT_FILE"
    fi
    
    if [ "$mem_usage" -gt "$HIGH_MEM_THRESHOLD" ]; then
        warning "High memory usage detected: ${mem_usage}%"
    else
        success "Memory usage is normal: ${mem_usage}%"
    fi
    
    # Show top CPU processes
    echo -e "\n${YELLOW}Top CPU Processes:${NC}"
    ps -arcwwwxo pid,command,%cpu | head -n 6
    echo "$cpu_processes"
    
    # Also write to email report if enabled
    if [ "$SEND_EMAIL" = true ]; then
        echo -e "\nTop CPU Processes:" >> "$EMAIL_REPORT_FILE"
        echo "$cpu_processes" >> "$EMAIL_REPORT_FILE"
    fi
    
    # Get CPU load
    # cpu_load=$(top -l 1 | grep "CPU usage" | sed 's/.*(\(.*%\))/\1/' | awk '{print $1}')
    # cpu_load=${cpu_load%?} # Remove the '%' symbol
    cpu_load=$(uptime | awk -F'load averages?: ' '{print $2}' | cut -d' ' -f1)
    log_message "CPU usage: ${cpu_load}%"
    
    # Also write to email report if enabled
    if [ "$SEND_EMAIL" = true ]; then
        echo -e "\nCPU usage: ${cpu_load}%" >> "$EMAIL_REPORT_FILE"
    fi
    
    if [ "$cpu_load" -gt "$HIGH_CPU_THRESHOLD" ]; then
        warning "High CPU usage detected: ${cpu_load}%"
    else
        success "CPU usage is normal: ${cpu_load}%"
    fi
    
    # Show system uptime
    echo -e "\n${YELLOW}System Uptime:${NC}"
    uptime_info=$(uptime)
    echo "$uptime_info"
    log_message "Uptime: $uptime_info"
    
    # Also write to email report if enabled
    if [ "$SEND_EMAIL" = true ]; then
        echo -e "\nSystem Uptime:" >> "$EMAIL_REPORT_FILE"
        echo "$uptime_info" >> "$EMAIL_REPORT_FILE"
    fi
}

# Function to suggest cleanup actions
suggest_cleanup() {
    header "Cleanup Suggestions"
    
    # Check for old package files (apt)
    if command -v apt-get >/dev/null 2>&1; then
        apt_cache_size=$(du -sh /var/cache/apt/archives 2>/dev/null | cut -f1)
        echo -e "APT cache size: ${YELLOW}$apt_cache_size${NC}"
        echo -e "You can free space with: ${GREEN}sudo apt-get clean${NC}"
        
        # Also write to email report if enabled
        if [ "$SEND_EMAIL" = true ]; then
            echo -e "\nAPT cache size: $apt_cache_size" >> "$EMAIL_REPORT_FILE"
            echo "You can free space with: sudo apt-get clean" >> "$EMAIL_REPORT_FILE"
        fi
    fi
    
    # Check for old package files (pacman)
    if command -v pacman >/dev/null 2>&1; then
        pacman_cache_size=$(du -sh /var/cache/pacman/pkg 2>/dev/null | cut -f1)
        echo -e "Pacman cache size: ${YELLOW}$pacman_cache_size${NC}"
        echo -e "You can free space with: ${GREEN}sudo pacman -Sc${NC}"
        
        # Also write to email report if enabled
        if [ "$SEND_EMAIL" = true ]; then
            echo -e "\nPacman cache size: $pacman_cache_size" >> "$EMAIL_REPORT_FILE"
            echo "You can free space with: sudo pacman -Sc" >> "$EMAIL_REPORT_FILE"
        fi
    fi
    
    # Check for old journals
    if command -v journalctl >/dev/null 2>&1; then
        journal_size=$(journalctl --disk-usage 2>/dev/null | grep "Archived" | awk '{print $7 $8}')
        echo -e "Journal logs size: ${YELLOW}$journal_size${NC}"
        echo -e "You can free space with: ${GREEN}sudo journalctl --vacuum-time=7d${NC}"
        
        # Also write to email report if enabled
        if [ "$SEND_EMAIL" = true ]; then
            echo -e "\nJournal logs size: $journal_size" >> "$EMAIL_REPORT_FILE"
            echo "You can free space with: sudo journalctl --vacuum-time=7d" >> "$EMAIL_REPORT_FILE"
        fi
    fi
    
    # Check for old snapshots (if using snapper)
    if command -v snapper >/dev/null 2>&1; then
        echo -e "You may have old snapshots taking up space."
        echo -e "Check with: ${GREEN}sudo snapper list${NC}"
        echo -e "Delete old ones with: ${GREEN}sudo snapper delete NUMBER${NC}"
        
        # Also write to email report if enabled
        if [ "$SEND_EMAIL" = true ]; then
            echo -e "\nSnapper snapshots:" >> "$EMAIL_REPORT_FILE"
            echo "Check with: sudo snapper list" >> "$EMAIL_REPORT_FILE"
            echo "Delete old ones with: sudo snapper delete NUMBER" >> "$EMAIL_REPORT_FILE"
        fi
    fi
    
    # Suggest cleaning unused packages
    if command -v apt-get >/dev/null 2>&1; then
        echo -e "Check for unused packages with: ${GREEN}sudo apt-get autoremove --dry-run${NC}"
        
        # Also write to email report if enabled
        if [ "$SEND_EMAIL" = true ]; then
            echo -e "\nCheck for unused packages with: sudo apt-get autoremove --dry-run" >> "$EMAIL_REPORT_FILE"
        fi
    elif command -v pacman >/dev/null 2>&1; then
        echo -e "Check for unused packages with: ${GREEN}pacman -Qtdq${NC}"
        
        # Also write to email report if enabled
        if [ "$SEND_EMAIL" = true ]; then
            echo -e "\nCheck for unused packages with: pacman -Qtdq" >> "$EMAIL_REPORT_FILE"
        fi
    fi
}

# Function to send email report
send_email_report() {
    if [ "$SEND_EMAIL" = true ] && [ ! -z "$EMAIL_RECIPIENT" ]; then
        header "Sending Email Report"

        echo -e "\n\n=== SUMMARY ===" >> "$EMAIL_REPORT_FILE"
        echo "Script executed on: $(date)" >> "$EMAIL_REPORT_FILE"
        echo "Hostname: $(hostname)" >> "$EMAIL_REPORT_FILE"
        echo "Log file location: $LOG_FILE" >> "$EMAIL_REPORT_FILE"
        echo "Backup directory: $BACKUP_DIR" >> "$EMAIL_REPORT_FILE"

        # Send email using msmtp
        if cat <<EOF | msmtp "$EMAIL_RECIPIENT"
Subject: $EMAIL_SUBJECT
From: $EMAIL_SENDER
To: $EMAIL_RECIPIENT

$(cat "$EMAIL_REPORT_FILE")
EOF
        then
            success "Email report sent to $EMAIL_RECIPIENT"
        else
            error "Failed to send email report"
        fi

        rm -f "$EMAIL_REPORT_FILE"
    fi
}

# Main function
main() {
    clear
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${BLUE}      System Doctor - Cleanup & Health Script     ${NC}"
    echo -e "${BLUE}==================================================${NC}"
    echo -e "Started at: $(date)"
    echo -e "Log file: $LOG_FILE"
    echo

    log_message "Script started"
    
    check_root
    setup_email
    
    # Prompt before proceeding
    echo -e "${YELLOW}This script will analyze your system and suggest cleanup actions.${NC}"
    echo -e "${YELLOW}It will also clean temporary files and cache directories.${NC}"
    echo -e "${RED}Some operations may require root privileges.${NC}"
    read -p "Do you want to proceed? (y/n): " confirm
    
    if [[ $confirm != [yY] ]]; then
        echo "Operation cancelled."
        log_message "Operation cancelled by user"
        exit 0
    fi
    
    create_backup
    clean_temp_files
    send_email_report
    analyze_disk_usage
    analyze_system_resources
    suggest_cleanup

    
    header "Summary"
    echo -e "System Doctor has completed its analysis and cleanup."
    echo -e "A log file has been saved to: ${GREEN}$LOG_FILE${NC}"
    echo -e "Critical files were backed up to: ${GREEN}$BACKUP_DIR${NC}"
    if [ "$SEND_EMAIL" = true ]; then
        echo -e "A report has been emailed to: ${GREEN}$EMAIL_RECIPIENT${NC}"
    fi
    
    log_message "Script completed successfully"
    
    echo
    echo -e "${BLUE}==================================================${NC}"
    echo -e "Completed at: $(date)"
    echo -e "${BLUE}==================================================${NC}"
}

# Run the main function
main

