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

# Ask for the password in the shell so there is a visible prompt. WEB_PASS may
# also come from the environment, or be left empty to use SSH keys.
if [ -z "$WEB_PASS" ] && [ -t 0 ]; then
    read -r -s -p "Password for ${WEB_USER}@${WEB_HOST}: " WEB_PASS
    echo
fi

# Create a temporary batch file for sftp
BATCH_FILE=$(mktemp)
LOCAL_ACCUM="$(pwd)/www/accum.png"
LOCAL_VERIF="$(pwd)/www/verif.png"
LOCAL_INSTALL="$(pwd)/www/install.sh"

if [ ! -f "$LOCAL_ACCUM" ]; then
    echo "Error: local file $LOCAL_ACCUM not found."
    exit 1
fi

if [ ! -f "$LOCAL_VERIF" ]; then
    echo "Error: local file $LOCAL_VERIF not found."
    exit 1
fi

if [ ! -f "$LOCAL_INSTALL" ]; then
    echo "Error: local file $LOCAL_INSTALL not found."
    exit 1
fi

cat <<EOF > "$BATCH_FILE"
cd ${REMOTE_DIR}
put "${LOCAL_INDEX}" index.html
put "${LOCAL_ACCUM}" accum.png
put "${LOCAL_VERIF}" verif.png
put "${LOCAL_INSTALL}" install.sh
quit
EOF

# Without a password, disable interactive prompts (BatchMode) so a missing
# credential fails fast instead of hanging. SSH key/agent auth still works.
if [ -n "$WEB_PASS" ]; then
    SFTP_OPTS="-oBatchMode=no"
else
    echo "No password provided - trying SSH key/agent authentication."
    SFTP_OPTS="-oBatchMode=yes"
fi
SFTP_OPTS="$SFTP_OPTS -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null"
if [ -n "$WEB_PASS" ]; then
    SSHPASS="$WEB_PASS" sshpass -e sftp $SFTP_OPTS -b "$BATCH_FILE" "${WEB_USER}@${WEB_HOST}"
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
