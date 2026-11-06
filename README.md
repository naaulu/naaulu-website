# Naaulu Website

Source of the `naaulu.org` landing page.

## Contents

- `www/index.html` — landing page (features, installation, quickstart, products)
- `www/live/index.html` — NAAULU Live rainfall viewer, served at `live.naaulu.org/`. Only this file comes from this repo: the frames, `<country>.json` and `countries.json` beside it belong to the box (the pipeline uploads the frames, a timer on the box writes the indexes), and this deploy never deletes them.
- `www/install.sh` — install script served at `naaulu.org/install.sh`
- `www/accum.png`, `www/verif.png` — example figures shown in the quickstart
- `deploy.sh` — phase 1 uploads the landing over SFTP, phase 2 rsyncs the viewer to the site box
- `.woodpecker/deploy.yml` — runs `deploy.sh` on push to `main`
- `bootstrap.sh` — provisions the site box on top of pylone

## Bootstrap the site box

`live.naaulu.org` is served by a box declared in pylone. Steps, in order:

1. Declare the site (the box must already be registered with `pylone add box`):

```bash
pylone add site --domain live.naaulu.org --box <box> --root /var/www/naaulu.org/live --mail hello@naaulu.org
```

2. Apply pylone's layer — security, firewall, Caddy, certificate:

```bash
pylone deploy --box <box>
```

3. Add a DNS `A` record for `live.naaulu.org` pointing at the box.

4. Run the bootstrap from a checkout of this repository **on the box**:

```bash
PIPELINE_PUB=/path/to/pipeline-key.pub \
CI_PUB=/path/to/ci-key.pub \
./bootstrap.sh
```

`bootstrap.sh` derives the domain and the document root from the Caddyfile, creates the document root, installs `rsync`, authorizes the keys, writes the index and retention timer, then runs the health checks. `--skip-keys` skips the key phase, `--help` prints the usage. Re-running it is safe.

5. Add the Woodpecker secrets for this repository: `WEB_HOST`, `WEB_USER`, `WEB_PASS` for the landing, and `DEPLOY_HOST`, `DEPLOY_PORT`, `DEPLOY_USER`, `DEPLOY_KEY` for the viewer. `DEPLOY_KEY` is the private key, base64-encoded on one line.

6. Point the pipeline at the box: `SFTP_TARGETS` in the [naaulu-live README](https://git.naaulu.org/naaulu/naaulu-live).

7. Verify:

```bash
curl -fsS https://live.naaulu.org/              # 200
curl -fsS https://live.naaulu.org/countries.json
./bootstrap.sh                                  # every phase reports [ok]
```

## Deploy

```bash
# landing -> web hosting, viewer -> site box (each phase needs its own set)
WEB_HOST=... WEB_USER=... WEB_PASS=... \
DEPLOY_HOST=... DEPLOY_PORT=... DEPLOY_USER=... DEPLOY_KEY=... \
./deploy.sh
```

Each phase runs only when its credentials are present, both are always attempted, and a failure in one does not hide the other.
