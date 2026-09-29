# Naaulu Website

Source of the `naaulu.org` landing page.

## Contents

- `www/index.html` — landing page (features, installation, quickstart, products)
- `www/install.sh` — install script served at `naaulu.org/install.sh`
- `www/accum.png`, `www/verif.png` — example figures shown in the quickstart
- `deploy.sh` — uploads `www/` to the hosting server over SFTP
- `.woodpecker/deploy.yml` — runs `deploy.sh` on push to `main`

## Deploy

```bash
WEB_HOST=... WEB_USER=... WEB_PASS=... ./deploy.sh
```
