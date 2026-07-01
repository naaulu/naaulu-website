#!/bin/bash
# Copyright (C) 2026 naaulu org
# Licensed under the GNU Affero General Public License v3.0 or later.
# See LICENSE file for details.

# Configuration from environment variables or parameters
WEB_HOST="${WEB_HOST:-$1}"
WEB_USER="${WEB_USER:-$2}"
WEB_PASS="${WEB_PASS:-}"
REMOTE_DIR="www"

# Check if required parameters are provided
if [ -z "$WEB_USER" ] || [ -z "$WEB_HOST" ]; then
    echo "Usage: WEB_HOST=... WEB_USER=... WEB_PASS=... ./deploy.sh"
    echo "   or: ./deploy.sh <host_address> <username>"
    echo "Example: WEB_HOST=ftp.clusterXXX.hosting.ovh.net WEB_USER=user-name WEB_PASS=password ./deploy.sh"
    exit 1
fi

# Get absolute path of the local index.html
LOCAL_INDEX="$(pwd)/www/index.html"

if [ ! -f "$LOCAL_INDEX" ]; then
    echo "Error: local file $LOCAL_INDEX not found."
    exit 1
fi

echo "Connecting to ${WEB_USER}@${WEB_HOST}..."

sshpass -p "$WEB_PASS" ssh -o StrictHostKeyChecking=no "${WEB_USER}@${WEB_HOST}" \
    "mkdir -p ${REMOTE_DIR}/live" 2>/dev/null || true

# Create a temporary batch file for sftp
BATCH_FILE=$(mktemp)
LOCAL_PLOT="$(pwd)/www/dove.png"
LOCAL_BEAVER="$(pwd)/www/dove_beaver.png"
LOCAL_INSTALL="$(pwd)/www/install.sh"

if [ ! -f "$LOCAL_PLOT" ]; then
    echo "Error: local file $LOCAL_PLOT not found."
    exit 1
fi

if [ ! -f "$LOCAL_BEAVER" ]; then
    echo "Error: local file $LOCAL_BEAVER not found."
    exit 1
fi

if [ ! -f "$LOCAL_INSTALL" ]; then
    echo "Error: local file $LOCAL_INSTALL not found."
    exit 1
fi

LOCAL_LIVE_INDEX="$(pwd)/www/live/index.html"
LOCAL_LIVE_COUNTRIES="$(pwd)/www/live/countries.json"

cat <<EOF > "$BATCH_FILE"
cd ${REMOTE_DIR}
put "${LOCAL_INDEX}" index.html
put "${LOCAL_PLOT}" dove.png
put "${LOCAL_BEAVER}" dove_beaver.png
put "${LOCAL_INSTALL}" install.sh
cd live
put "${LOCAL_LIVE_INDEX}" index.html
put "${LOCAL_LIVE_COUNTRIES}" countries.json
quit
EOF

# Execute sftp with sshpass if password provided, otherwise use regular sftp
SFTP_OPTS="-oBatchMode=no -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null"
if [ -n "$WEB_PASS" ]; then
    sshpass -p "$WEB_PASS" sftp $SFTP_OPTS -b "$BATCH_FILE" "${WEB_USER}@${WEB_HOST}"
else
    sftp $SFTP_OPTS -b "$BATCH_FILE" "${WEB_USER}@${WEB_HOST}"
fi

# Check the exit status of the sftp command
if [ $? -eq 0 ]; then
    echo "----------------------------"
    echo "Deployment complete!"
    echo "Your site should be live at: http://$(echo $WEB_HOST | cut -d. -f2-).ovh.net/~${WEB_USER}/ (or your domain)"
else
    echo "----------------------------"
    echo "Deployment FAILED! Please check the error message above."
    echo "Note: If 'rm index.html' failed, it might just mean the file was already deleted."
    rm "$BATCH_FILE"
    exit 1
fi

# Clean up
rm "$BATCH_FILE"
