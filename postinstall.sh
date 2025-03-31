#!/bin/bash

# === VARIABLES ===
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_DIR="./logs"
LOG_FILE="$LOG_DIR/postinstall_$TIMESTAMP.log"
CONFIG_DIR="./config"
PACKAGE_LIST="./lists/packages.txt"
USERNAME=$(logname)
USER_HOME="/home/$USERNAME"

# === FUNCTIONS ===
# Function to log actions
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to check and install packages
check_and_install() {
  local pkg=$1
  if dpkg -s "$pkg" &>/dev/null; then
    log "$pkg is already installed."
  else
    log "Installing $pkg..."
    apt install -y "$pkg" &>>"$LOG_FILE"
    if [ $? -eq 0 ]; then
      log "$pkg successfully installed."
    else
      log "Failed to install $pkg."
    fi
  fi
}

# Function to ask a yes/no question
ask_yes_no() {
  read -p "$1 [y/N]: " answer
  case "$answer" in
    [Yy]* ) return 0 ;;
    * ) return 1 ;;
  esac
}


# === INITIAL SETUP ===
# Create log directory, log file and log script startup with who is running him
mkdir -p "$LOG_DIR"
touch "$LOG_FILE"
log "Starting post-installation script. Logged user: $USERNAME"

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then
  log "This script must be run as root."
  exit 1
fi


# === 1. SYSTEM UPDATE ===
# Update packages and log results
log "Updating system packages..."
apt update && apt upgrade -y &>>"$LOG_FILE"


# === 2. PACKAGE INSTALLATION ===
# test if package list file exists, then read it and install packages if they are not already installed else skip
if [ -f "$PACKAGE_LIST" ]; then
  log "Reading package list from $PACKAGE_LIST"
  while IFS= read -r pkg || [[ -n "$pkg" ]]; do
    [[ -z "$pkg" || "$pkg" =~ ^# ]] && continue
    check_and_install "$pkg"
  done < "$PACKAGE_LIST"
else
  log "Package list file $PACKAGE_LIST not found. Skipping package installation."
fi


# === 3. UPDATE MOTD ===
# test if motd.txt file exists, then copy it to /etc/motd and log it else skip
if [ -f "$CONFIG_DIR/motd.txt" ]; then
  cp "$CONFIG_DIR/motd.txt" /etc/motd
  log "MOTD updated."
else
  log "motd.txt not found."
fi


# === 4. CUSTOM .bashrc ===
# test if bashrc.append file exists, then copy it to bashrc, change owner and log it else skip
if [ -f "$CONFIG_DIR/bashrc.append" ]; then
  cat "$CONFIG_DIR/bashrc.append" >> "$USER_HOME/.bashrc"
  chown "$USERNAME:$USERNAME" "$USER_HOME/.bashrc"
  log ".bashrc customized."
else
  log "bashrc.append not found."
fi


# === 5. CUSTOM .nanorc ===
# test if nanorc.append file exists, then copy it to nanorc, change owner and log it else skip
if [ -f "$CONFIG_DIR/nanorc.append" ]; then
  cat "$CONFIG_DIR/nanorc.append" >> "$USER_HOME/.nanorc"
  chown "$USERNAME:$USERNAME" "$USER_HOME/.nanorc"
  log ".nanorc customized."
else
  log "nanorc.append not found."
fi


# === 6. ADD SSH PUBLIC KEY ===
# test if user wants to add a public SSH key and create it if he wants
if ask_yes_no "Would you like to add a public SSH key?"; then
  read -p "Paste your public SSH key: " ssh_key
  mkdir -p "$USER_HOME/.ssh"
  echo "$ssh_key" >> "$USER_HOME/.ssh/authorized_keys"
  chown -R "$USERNAME:$USERNAME" "$USER_HOME/.ssh"
  chmod 700 "$USER_HOME/.ssh"
  chmod 600 "$USER_HOME/.ssh/authorized_keys"
  log "SSH public key added."
fi


# === 7. SSH CONFIGURATION: KEY AUTH ONLY ===
# test if sshd_config file exists, then modify it to accept key-based authentication only and log it else skip
if [ -f /etc/ssh/sshd_config ]; then
  sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
  sed -i 's/^#\?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config
  sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
  systemctl restart ssh
  log "SSH configured to accept key-based authentication only."
else
  log "sshd_config file not found."
fi

# log script completion
log "Post-installation script completed."

exit 0