#!/bin/bash
# bootstrap.sh — bring a fresh box to a full live.naaulu.org server, and
# double as the documentation for everything that sits ON TOP of pylone.
#
# WHAT THIS DOES NOT DO: OS hardening, firewall, Caddy, certificates or DNS.
# That is pylone's declared layer — 'pylone deploy' from the operator's
# machine, [[sites]] stanza in ~/.pylone/pylone.toml. Run that first; this
# script verifies it happened, then builds the rest: document root, rsync,
# deploy keys, the index and retention timer, health.
#
# The pipeline side (which box pushes frames, and how) is documented in
# naaulu-live's README. This script only prepares the box that receives the
# frames and serves the viewer.
#
# IDEMPOTENCY CONTRACT: every phase creates-if-missing (root, keys), writes-
# if-changed (script, units) or is a no-op when done (enable, start, install).
# Re-running this script is always safe.
#
# USAGE (as debian or root, from a checkout of this repo on the box):
#   PIPELINE_PUB=/path/to/pipeline-key.pub \
#   CI_PUB=/path/to/ci-key.pub \
#   ./bootstrap.sh
#
# The public keys are read from the given files at run time and appended to
# the deploy user's authorized_keys. Neither the keys nor any connection
# detail is stored in this repository.
#
# ENVIRONMENT
#   BOX / DOMAIN / ROOT / DEPLOY_USER / KEEP   all optional, derived when
#   possible from the Caddyfile pylone wrote.
set -euo pipefail

SKIP_KEYS=0
for arg in "$@"; do
    case "$arg" in
        --skip-keys) SKIP_KEYS=1 ;;
        -h|--help)   sed -n '2,30p' "$0"; exit 0 ;;
        *) echo "unknown argument: $arg"; exit 1 ;;
    esac
done

# Privilege: root directly, or passwordless sudo (pylone boxes have it).
if [ "$(id -u)" = 0 ]; then
    SUDO=""
    DEPLOY_USER="${SUDO_USER:-debian}"
elif sudo -n true 2>/dev/null; then
    SUDO="sudo"
    DEPLOY_USER="$(id -un)"
else
    echo "Error: run as root or as a user with passwordless sudo."
    exit 1
fi
DEPLOY_USER="${DEPLOY_USER_OVERRIDE:-$DEPLOY_USER}"

say()  { printf '\n=== %s ===\n' "$*"; }
ok()   { echo "  [ok] $*"; }
note() { echo "  [-] $*"; }

# ---------------------------------------------------------------------------
say "0. Preconditions (pylone's layer)"
# ---------------------------------------------------------------------------
CADDYFILE=/etc/caddy/Caddyfile
if [ ! -f "$CADDYFILE" ]; then
    echo "Error: no Caddyfile - run 'pylone deploy' first (box + [[sites]] declared)."
    exit 1
fi
$SUDO systemctl is-active --quiet caddy || {
    echo "Error: caddy not active - run 'pylone deploy' first."; exit 1; }
ok "caddy active"

# The first non-service block is this box's site; the root directive inside it
# is where the viewer and the frames live.
DOMAIN="${DOMAIN:-$($SUDO grep -E '^[a-z0-9.-]+ \{' "$CADDYFILE" | head -1 | cut -d' ' -f1 | tr -d ' {')}"
[ -n "$DOMAIN" ] || { echo "Error: domain not detected - set DOMAIN=."; exit 1; }
ROOT="${ROOT:-$($SUDO grep -E '^ *root \*' "$CADDYFILE" | head -1 | awk '{print $3}')}"
ROOT="${ROOT:-/var/www/$DOMAIN}"
ok "domain $DOMAIN"
ok "document root $ROOT"

# ---------------------------------------------------------------------------
say "1. Directories (created once, never touched again)"
# ---------------------------------------------------------------------------
# The document root is served by Caddy but written by the pipeline and by CI:
# /var/www belongs to root, so the target must exist and belong to the
# deploying user.
$SUDO install -d -o "$DEPLOY_USER" -g "$DEPLOY_USER" "$ROOT"
ok "$ROOT owned by $DEPLOY_USER"

# ---------------------------------------------------------------------------
say "2. rsync (CI's transfer to this box)"
# ---------------------------------------------------------------------------
if command -v rsync >/dev/null 2>&1; then
    ok "rsync $(rsync --version | head -1 | awk '{print $3}')"
else
    $SUDO apt-get update -qq
    $SUDO apt-get install -y -qq rsync >/dev/null
    ok "rsync installed"
fi

# ---------------------------------------------------------------------------
say "3. Deploy keys"
# ---------------------------------------------------------------------------
AUTH_KEYS="/home/$DEPLOY_USER/.ssh/authorized_keys"
if [ "$SKIP_KEYS" = 1 ]; then
    note "skipped (--skip-keys)"
else
    added=0
    for var in PIPELINE_PUB CI_PUB; do
        path="${!var:-}"
        if [ -z "$path" ]; then
            note "$var not set - skipped"
            continue
        fi
        [ -f "$path" ] || { echo "Error: $path not found."; exit 1; }
        $SUDO install -d -m 700 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "/home/$DEPLOY_USER/.ssh"
        $SUDO touch "$AUTH_KEYS"
        $SUDO chmod 600 "$AUTH_KEYS"
        $SUDO chown "$DEPLOY_USER:$DEPLOY_USER" "$AUTH_KEYS"
        while IFS= read -r line; do
            [ -n "$line" ] || continue
            if ! grep -qxF "$line" "$AUTH_KEYS" 2>/dev/null; then
                printf '%s\n' "$line" | $SUDO tee -a "$AUTH_KEYS" >/dev/null
                added=$((added + 1))
            fi
        done < "$path"
        ok "$var authorized"
    done
    ok "$added key line(s) added, $(grep -c . "$AUTH_KEYS" 2>/dev/null || echo 0) total"
fi

# ---------------------------------------------------------------------------
say "4. Index and retention timer"
# ---------------------------------------------------------------------------
# The viewer reads its country and frame lists from files this timer writes;
# it also prunes to KEEP files per country and duration.
KEEP="${KEEP:-400}"

$SUDO tee /usr/local/sbin/naaulu-live-manage >/dev/null <<MANAGE
#!/bin/bash
# Index and retention for the live site document root.
#   countries.json  - country codes discovered in the directory
#   <code>.json     - sorted png names for one country
#   prune           - newest KEEP files per country and duration
set -euo pipefail

ROOT=$ROOT
KEEP=$KEEP

[ -d "\$ROOT" ] || exit 0
cd "\$ROOT"

names=\$(find . -maxdepth 1 -name '*.png' -printf '%f\n')

# Positional split of <stamp>.<code>.<duration>.<resolution>.<product>.png
codes=\$(printf '%s\n' "\$names" | sed -nE 's/^[0-9]{14}\.([A-Za-z0-9]+)\..*/\1/p' | LC_ALL=C sort -u)
durations=\$(printf '%s\n' "\$names" | sed -nE 's/^[0-9]{14}\.[A-Za-z0-9]+\.([A-Za-z0-9]+)\..*/\1/p' | LC_ALL=C sort -u)

# retention: newest KEEP per country and duration
for code in \$codes; do
    for dur in \$durations; do
        mapfile -t files < <(find . -maxdepth 1 -name "*.\${code}.\${dur}.*.png" -printf '%f\n' | LC_ALL=C sort)
        n=\${#files[@]}
        (( n > KEEP )) || continue
        for ((i = 0; i < n - KEEP; i++)); do
            rm -f -- "\${files[i]}"
        done
    done
done

# <code>.json: sorted png names for one country
for code in \$codes; do
    find . -maxdepth 1 -name "*.\${code}.*.png" -printf '%f\n' | LC_ALL=C sort \\
      | awk 'BEGIN{printf "["} {printf "%s\\"%s\\"", (NR>1?",":""), \$0} END{printf "]\\n"}' \\
      > ".idx.\$\$"
    mv -f ".idx.\$\$" "\${code}.json"
    chmod 644 "\${code}.json"
done

# countries.json: codes present, with their display names
country_name() {
    case "\$1" in
        bel) echo "Belgium" ;;
        est) echo "Estonia" ;;
        lux) echo "Luxembourg" ;;
        nld) echo "Netherlands" ;;
        *)   echo "\$1" ;;
    esac
}
{
    printf '['
    first=1
    for code in \$codes; do
        [ "\$first" = 1 ] || printf ','
        printf '{"code":"%s","name":"%s"}' "\$code" "\$(country_name "\$code")"
        first=0
    done
    printf ']\\n'
} > ".idx.\$\$"
mv -f ".idx.\$\$" countries.json
chmod 644 countries.json

echo "indexed: \$(printf '%s' "\$codes" | tr '\\n' ' ')| durations: \$(printf '%s' "\$durations" | tr '\\n' ' ')"
MANAGE
$SUDO chmod 755 /usr/local/sbin/naaulu-live-manage
ok "/usr/local/sbin/naaulu-live-manage (KEEP=$KEEP)"

$SUDO tee /etc/systemd/system/naaulu-live-manage.service >/dev/null <<'UNIT'
[Unit]
Description=Index and retention for the naaulu live site

[Service]
Type=oneshot
User=debian
Group=debian
ExecStart=/usr/local/sbin/naaulu-live-manage
UNIT

$SUDO tee /etc/systemd/system/naaulu-live-manage.timer >/dev/null <<'UNIT'
[Unit]
Description=Run naaulu-live-manage every minute

[Timer]
OnBootSec=1min
OnUnitActiveSec=1min

[Install]
WantedBy=timers.target
UNIT

$SUDO systemctl daemon-reload
$SUDO systemctl enable --now naaulu-live-manage.timer >/dev/null 2>&1
$SUDO systemctl restart naaulu-live-manage.service
ok "timer active, first run done"

# ---------------------------------------------------------------------------
say "5. Health"
# ---------------------------------------------------------------------------
if curl -fsS --max-time 20 -o /dev/null "https://$DOMAIN/"; then
    ok "https://$DOMAIN/ serves"
else
    echo "Error: https://$DOMAIN/ did not answer."; exit 1
fi

$SUDO systemctl is-active --quiet naaulu-live-manage.timer && ok "timer active" || {
    echo "Error: timer not active."; exit 1; }

if [ -s "$ROOT/countries.json" ] && grep -q '^\[' "$ROOT/countries.json"; then
    ok "countries.json: $(cat "$ROOT/countries.json")"
else
    echo "Error: countries.json missing or malformed."; exit 1
fi

pngs=$(find "$ROOT" -maxdepth 1 -name '*.png' | wc -l)
frames=$(find "$ROOT" -maxdepth 1 -name '*.png' -printf '%f\n' | head -1)
ok "$pngs frame(s) present${frames:+, newest: $frames}"

printf '\nAll phases ok. The pipeline may now target %s.\n' "$ROOT"
