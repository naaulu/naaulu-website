# Naaulu Website

Source of the `naaulu.org` landing page.

## Contents

- `www/index.html` — landing page (features, installation, quickstart, products)
- `www/live/index.html`, `www/live/countries.json` — NAAULU Live rainfall viewer, served at `naaulu.org/live/`. Only these two files are deployed from this repo: the PNGs and `<country>.json` indexes in that directory are uploaded by the [naaulu-live](https://github.com/naaulu/naaulu-live) data pipeline and must never be deleted by this deploy.
- `www/install.sh` — install script served at `naaulu.org/install.sh`
- `www/accum.png`, `www/verif.png` — example figures shown in the quickstart
- `deploy.sh` — uploads `www/` to the hosting server over SFTP
- `.woodpecker/deploy.yml` — runs `deploy.sh` on push to `main`

## Deploy

```bash
WEB_HOST=... WEB_USER=... WEB_PASS=... ./deploy.sh
```
