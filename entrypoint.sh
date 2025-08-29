#!/bin/sh
set -e

# --- 1. Validate required environment variables ---
: "${PROXY_HOST?PROXY_HOST environment variable is not set}"
: "${PROXY_PORT?PROXY_PORT environment variable is not set}"

# --- 2. Set default values for optional variables ---
PROXY_TYPE=${PROXY_TYPE:-socks5} # Default to socks5 if not specified
EXCLUDE_CIDR=${EXCLUDE_CIDR:-}   # By default, no extra networks are excluded

# --- 3. Generate redsocks.conf from the template ---
TEMPLATE="/etc/redsocks/redsocks.conf.template"
CONFIG_FILE="/etc/redsocks/redsocks.conf"

# Replace the main placeholders with values from env vars
sed -e "s/__PROXY_HOST__/${PROXY_HOST}/" \
    -e "s/__PROXY_PORT__/${PROXY_PORT}/" \
    -e "s/__PROXY_TYPE__/${PROXY_TYPE}/" \
    "$TEMPLATE" > "$CONFIG_FILE"

# --- 4. Add authentication block if user/pass are provided ---
if [ -n "$PROXY_USER" ] && [ -n "$PROXY_PASS" ]; then
    echo "    login = \"${PROXY_USER}\";" >> "$CONFIG_FILE"
    echo "    password = \"${PROXY_PASS}\";" >> "$CONFIG_FILE"
    echo "Authentication details added to redsocks.conf"
fi

# --- 5. Configure iptables for transparent proxying ---
# Create a new chain for our redirection rules
iptables -t nat -N REDSOCKS

# Standard exclusions for local, private, and special-use networks
iptables -t nat -A REDSOCKS -d 0.0.0.0/8 -j RETURN
iptables -t nat -A REDSOCKS -d 10.0.0.0/8 -j RETURN
iptables -t nat -A REDSOCKS -d 127.0.0.0/8 -j RETURN
iptables -t nat -A REDSOCKS -d 169.254.0.0/16 -j RETURN
iptables -t nat -A REDSOCKS -d 172.16.0.0/12 -j RETURN
iptables -t nat -A REDSOCKS -d 192.168.0.0/16 -j RETURN
iptables -t nat -A REDSOCKS -d 224.0.0.0/4 -j RETURN
iptables -t nat -A REDSOCKS -d 240.0.0.0/4 -j RETURN

# Exclude user-defined networks (e.g., for other Docker services like databases)
# Supports comma-separated values in EXCLUDE_CIDR
if [ -n "$EXCLUDE_CIDR" ]; then
    for cidr in $(echo $EXCLUDE_CIDR | sed "s/,/ /g"); do
        iptables -t nat -A REDSOCKS -d $cidr -j RETURN
        echo "Excluding network $cidr from proxy"
    done
fi

# Exclude the proxy server itself to prevent traffic loops
iptables -t nat -A REDSOCKS -d ${PROXY_HOST} -j RETURN

# Redirect all other outgoing TCP traffic to the local redsocks port
iptables -t nat -A REDSOCKS -p tcp -j REDIRECT --to-ports 12345

# Apply the REDSOCKS chain to all outgoing traffic from this container
iptables -t nat -A OUTPUT -p tcp -j REDSOCKS

echo "iptables rules applied successfully."

# --- 6. Execute redsocks with the final configuration ---
echo "Starting redsocks..."
exec redsocks -c "$CONFIG_FILE"
