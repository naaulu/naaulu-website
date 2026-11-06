#!/bin/bash
# Copyright (C) 2026 naaulu org
# Licensed under the GNU Affero General Public License v3.0 or later.
# See LICENSE file for details.
#
# Two phases, one per destination:
#
#   phase 1  landing + terms  ->  web hosting      (sftp, password)
#   phase 2  viewer (live/)   ->  the site box      (rsync, key)
#
# Each phase runs only when its credentials are present, and both are always
# attempted: a failure in one does not hide the other. Nothing phase 2 touches
# is a file phase 1 owns, and neither phase deletes anything on the server.

set -uo pipefail

# ---- phase 1: static pages to the web host --------------------------------
WEB_HOST="${WEB_HOST:-${1:-}}"
WEB_USER="${WEB_USER:-${2:-}}"
WEB_PASS="${WEB_PASS:-}"
REMOTE_DIR="www"

# ---- phase 2: viewer to the site box --------------------------------------
DEPLOY_HOST="${DEPLOY_HOST:-}"
DEPLOY_PORT="${DEPLOY_PORT:-}"
DEPLOY_USER="${DEPLOY_USER:-}"
DEPLOY_KEY="${DEPLOY_KEY:-$HOME/.ssh/id_ed25519}"
DEPLOY_ROOT="${DEPLOY_ROOT:-/var/www/naaulu.org/live}"

if [ -z "$WEB_HOST" ] && [ -z "$DEPLOY_HOST" ]; then
    cat <<'EOF'
Usage: set credentials for the phase(s) you want to deploy:

  # landing/terms -> web hosting
  WEB_HOST=... WEB_USER=... WEB_PASS=...  ./deploy.sh

  # viewer -> site box
  DEPLOY_HOST=... DEPLOY_PORT=... DEPLOY_USER=... DEPLOY_KEY=path ./deploy.sh

  (both sets set: one run deploys everything)
EOF
    exit 1
fi

[ -d www ] || { echo "Error: www/ not found - run from the repo root."; exit 1; }

rc=0

# ---- phase 1 ---------------------------------------------------------------
if [ -n "$WEB_HOST" ]; then
    LOCAL_INDEX="$(pwd)/www/index.html"
    LOCAL_ACCUM="$(pwd)/www/accum.png"
    LOCAL_VERIF="$(pwd)/www/verif.png"
    LOCAL_INSTALL="$(pwd)/www/install.sh"
    for f in "$LOCAL_INDEX" "$LOCAL_ACCUM" "$LOCAL_VERIF" "$LOCAL_INSTALL"; do
        [ -f "$f" ] || { echo "Error: local file $f not found."; exit 1; }
    done

    echo "Publishing landing to ${WEB_USER}@${WEB_HOST}:${REMOTE_DIR} ..."

    # Ask for the password in the shell so there is a visible prompt. WEB_PASS
    # may also come from the environment, or be left empty to use SSH keys.
    if [ -z "$WEB_PASS" ] && [ -t 0 ]; then
        read -r -s -p "Password for ${WEB_USER}@${WEB_HOST}: " WEB_PASS
        echo
    fi

    BATCH_FILE=$(mktemp)
    trap 'rm -f "$BATCH_FILE"' EXIT
    cat <<EOF > "$BATCH_FILE"
cd ${REMOTE_DIR}
put "${LOCAL_INDEX}" index.html
put "${LOCAL_ACCUM}" accum.png
put "${LOCAL_VERIF}" verif.png
put "${LOCAL_INSTALL}" install.sh
ls -l
quit
EOF

    # Commands go on STDIN, never with sftp -b: batch mode refuses to prompt
    # for passwords by design, which would silence sshpass (its only job is
    # answering that prompt).
    if [ -n "$WEB_PASS" ]; then
        SFTP_CMD=(env SSHPASS="$WEB_PASS" sshpass -e sftp)
        SFTP_OPTS="-oBatchMode=no"
    else
        echo "No password provided - trying SSH key/agent authentication."
        SFTP_CMD=(sftp)
        SFTP_OPTS="-oBatchMode=yes"
    fi
    SFTP_OPTS="$SFTP_OPTS -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null"

    if sftp_out=$("${SFTP_CMD[@]}" $SFTP_OPTS "${WEB_USER}@${WEB_HOST}" < "$BATCH_FILE" 2>&1); then
        sftp_rc=0
    else
        sftp_rc=$?
    fi
    printf '%s\n' "$sftp_out" | grep -v "^Warning:"

    # sftp exits 0 even when a command fails, and a failed write leaves a
    # truncated file behind, so compare what the server reports against what
    # was sent rather than trusting the exit status.
    declare -A remote_size=()
    while read -r sz nm; do
        [ -n "$nm" ] || continue
        remote_size["$nm"]="$sz"
    done < <(printf '%s\n' "$sftp_out" | awk '/^-/ {print $5, $NF}')

    verify_rc=0
    for pair in "index.html:$LOCAL_INDEX" "accum.png:$LOCAL_ACCUM" \
               "verif.png:$LOCAL_VERIF" "install.sh:$LOCAL_INSTALL"; do
        remote_name="${pair%%:*}"
        local_file="${pair#*:}"
        want=$(wc -c < "$local_file")
        got=${remote_size[$remote_name]:-absent}
        if [ "$want" != "$got" ]; then
            echo "  [fail] $remote_name: sent ${want} bytes, server reports ${got}"
            verify_rc=1
        fi
    done

    if [ "$sftp_rc" -eq 0 ] && [ "$verify_rc" -eq 0 ]; then
        echo "  [ok] landing published"
    else
        echo "  [fail] landing publish (sftp=$sftp_rc verify=$verify_rc)"
        rc=1
    fi
else
    echo "  [-] WEB_HOST not set - skipping landing"
fi

# ---- phase 2 ---------------------------------------------------------------
if [ -n "$DEPLOY_HOST" ]; then
    [ -f "$DEPLOY_KEY" ] || { echo "Error: deploy key $DEPLOY_KEY not found."; exit 1; }
    [ -n "$DEPLOY_PORT" ] || { echo "Error: DEPLOY_PORT is required (non-standard ssh port)."; exit 1; }
    [ -f www/live/index.html ] || { echo "Error: www/live/index.html not found."; exit 1; }

    echo "Publishing viewer to ${DEPLOY_USER}@${DEPLOY_HOST}:${DEPLOY_ROOT} ..."

    # No --delete: the frames, <country>.json and countries.json in that
    # directory are owned by the pipeline and the site's own timer.
    if rsync -az --chmod=D755,F644 \
        -e "ssh -i $DEPLOY_KEY -p $DEPLOY_PORT -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15 -o ServerAliveInterval=15 -o ServerAliveCountMax=4" \
        www/live/ "${DEPLOY_USER}@${DEPLOY_HOST}:${DEPLOY_ROOT}/"; then
        echo "  [ok] viewer published"
    else
        echo "  [fail] viewer publish"
        rc=1
    fi
else
    echo "  [-] DEPLOY_HOST not set - skipping viewer"
fi

echo "----------------------------"
if [ "$rc" -eq 0 ]; then
    echo "Deployment complete."
else
    echo "Deployment FAILED - see the errors above."
fi
exit "$rc"
