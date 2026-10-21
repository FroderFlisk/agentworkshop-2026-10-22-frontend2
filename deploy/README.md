# Deploy

This is the small half: sending `board/` to a server that is already set up.

```bash
printf 'root@<server-ip>\n' > .deploy-host   # gitignored, done once
deploy/deploy.sh                             # or: HOST=root@<server-ip> deploy/deploy.sh
```

**`.deploy-host` is not optional during the day.** `tools/release.sh deploy` runs this script, and without the
file the whole release round stops. Whoever runs releases needs three things in their own clone: merge rights
in the repo, an ssh key the server accepts, and `.deploy-host` in the repo root. The organiser's tooling writes
the file in its own clone; if you run releases from another clone, write it yourself with the line above.

The script rsyncs `board/`, installs the systemd unit, restarts the service, makes sure the domain has a site in
the Caddyfile, and checks health. It can be run any number of times.
`qr.png` and `qr.svg` are excluded on purpose: they are gitignored and missing from a fresh clone, so without
the exclusion `--delete` would remove the big screen's qr code from the server on the day's first deploy.

**No secrets here.** This repository is public. The service's secrets (`LEAD_TOKEN`) live only on the server, in
`/etc/torget/<service>.env` (readable by root only), written by the organiser's tooling. The unit file names that
file with `EnvironmentFile=-...`; the leading `-` means the board still starts without it.

Setting up the server from scratch (Node, Caddy, firewall, DNS) belongs to whoever runs the workshop, not to
this repo.

`torget.service`, `Caddyfile.snippet` and `deploy.sh` contain placeholders (`8183`, `frontend2.torget.bjarby.com`,
`torget-frontend2`, `/opt/torget-frontend2`, `/var/lib/torget-frontend2`, `frontend2`, `FrontEnd 2`, `http://127.0.0.1:8180`,
`https://torget.bjarby.com`, `/var/www/torget-data`) that are filled in when the repo is built from the template.
No IP address and no domain is written into the repo.
