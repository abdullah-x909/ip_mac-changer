#!/bin/bash

# Function to check and install required packages
install_requirements() {
    for pkg in macchanger tor; do
        if ! command -v $pkg >/dev/null 2>&1; then
            echo "Installing $pkg..."
            if command -v apt >/dev/null 2>&1; then
                sudo apt update && sudo apt install -y "$pkg"
            elif command -v dnf >/dev/null 2>&1; then
                sudo dnf install -y "$pkg"
            elif command -v pacman >/dev/null 2>&1; then
                sudo pacman -Sy --noconfirm "$pkg"
            else
                echo "Unsupported package manager! Please install $pkg manually."
                exit 1
            fi
        fi
    done
}

# Detect Linux Distro
get_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$NAME"
    elif command -v lsb_release >/dev/null 2>&1; then
        lsb_release -si
    else
        echo "Unknown"
    fi
}

# Auto-detect main network interface (non-loopback, UP)
get_interface() {
    ip -o link show | awk -F': ' '{print $2}' | grep -v lo | head -n1
}

# Change MAC address (requires macchanger)
change_mac() {
    local iface="$1"
    sudo ip link set "$iface" down
    sudo macchanger -r "$iface" >/dev/null
    sudo ip link set "$iface" up
}

# Restart Tor to get new IP
change_tor_ip() {
    echo "Restarting Tor service to change IP..."
    sudo systemctl restart tor || sudo service tor restart
    sleep 5
}

# Add script to startup using crontab
add_to_startup() {
    script_path="$(realpath "$0")"
    crontab -l 2>/dev/null | grep -q "$script_path" && return
    (crontab -l 2>/dev/null; echo "@reboot bash $script_path &") | crontab -
    echo "Added to startup using crontab."
}

# Main function
main() {
    install_requirements

    distro=$(get_distro)
    echo "Detected distro: $distro"

    iface=$(get_interface)
    if [ -z "$iface" ]; then
        echo "No network interface found!"
        exit 1
    fi
    echo "Using interface: $iface"

    read -p "Enter delay between MAC/IP changes (in seconds): " delay
    delay=${delay:-30}
    echo "Delay set to $delay seconds."

    add_to_startup

    while true; do
        echo "Changing MAC address for $iface..."
        change_mac "$iface"
        echo "Requesting new Tor IP..."
        change_tor_ip
        echo "Done. Next change in $delay seconds."
        sleep "$delay"
    done
}

main
