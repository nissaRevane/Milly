# Deploying Milly on an OVH VPS

Milly is deployed with [Kamal 2](https://kamal-deploy.org), the Rails 8 deployment tool.
Everything runs on the single VPS as Docker containers; GitHub Actions builds the image
and drives the deploy.

## What ends up on the VPS

```
                  :443 / :80
                      |
              [ kamal-proxy ]  <- terminates TLS, renews Let's Encrypt certs
                      |
              [ milly-web ]    <- Puma, RAILS_ENV=production, non-root
                      |         (docker network "kamal", no published port)
              [ milly-db  ]    <- postgres:16-alpine
                                 data in /root/milly-db/data
```

The database is **not** reachable from the internet: it has no published port and only
answers on the internal `kamal` Docker network.

Deploys are zero-downtime. Kamal boots the new container, waits for `/up` to return 200,
switches the proxy over, then stops the old one.

---

## Requirements

- An OVH VPS with **at least 2 GB of RAM**, Debian 12 or Ubuntu 22.04+, root SSH access.
- A domain name with an `A` record pointing at the VPS IP.
- Ruby 3.3.6 locally (only for the one-time bootstrap commands).

---

## One-time setup

### 1. Fill in your values

Three placeholders in [config/deploy.yml](config/deploy.yml) are marked `<< A ADAPTER >>`:

| Key | Value |
|:---|:---|
| `servers.web[0]` and `accessories.db.host` | the VPS public IP |
| `proxy.host` and `env.clear.APP_HOST` | your domain, e.g. `milly.mondomaine.fr` |

Also set `registry.username` and `image` if you fork the repo under another account.
`image` must be **lowercase** — GHCR rejects uppercase paths.

### 2. Create a deploy SSH key

On your machine:

```bash
ssh-keygen -t ed25519 -C "milly-deploy" -f ~/.ssh/milly_deploy -N ""
ssh-copy-id -i ~/.ssh/milly_deploy.pub root@<VPS_IP>
ssh -i ~/.ssh/milly_deploy root@<VPS_IP> "echo ok"
```

### 3. Generate the secrets

```bash
# 128 hex chars, used to sign sessions and cookies
docker compose run --rm web bin/rails secret

# database password
openssl rand -base64 32 | tr -d '/+=' | head -c 32; echo
```

Keep both somewhere safe (a password manager). **Changing `SECRET_KEY_BASE` later logs
everyone out**; changing `POSTGRES_PASSWORD` after the first boot requires changing it
inside Postgres too, since the accessory only reads it when it initialises its data dir.

### 4. Register them with GitHub

In the repository, *Settings → Secrets and variables → Actions*:

**Secrets**

| Name | Value |
|:---|:---|
| `SSH_PRIVATE_KEY` | full contents of `~/.ssh/milly_deploy` (including the BEGIN/END lines) |
| `SECRET_KEY_BASE` | from step 3 |
| `POSTGRES_PASSWORD` | from step 3 |
| `SMTP_PASSWORD` | your SMTP password (see *Email* below) |

**Variables**

| Name | Value |
|:---|:---|
| `VPS_HOST` | the VPS public IP — used to pin the host key before deploying |

`KAMAL_REGISTRY_PASSWORD` is not needed: the workflow uses the automatic `GITHUB_TOKEN`
to push to GHCR.

### 5. Prepare the VPS

These three commands only talk to the server over SSH — no image is built locally, so they
run in seconds even from an Apple Silicon Mac.

```bash
bundle install

set -a; source .kamal/env.local; set +a   # see below
bundle exec kamal server bootstrap        # installs Docker on the VPS
bundle exec kamal proxy boot              # starts kamal-proxy on :80/:443
bundle exec kamal accessory boot db       # starts Postgres + creates its data dir
```

`.kamal/env.local` is git-ignored and holds the same values you put in GitHub:

```bash
export KAMAL_REGISTRY_PASSWORD=<a GitHub PAT with write:packages>
export SECRET_KEY_BASE=<from step 3>
export POSTGRES_PASSWORD=<from step 3>
export SMTP_PASSWORD=<your SMTP password>
```

### 6. First deploy

Push to `master`, or run the **CI & Deploy** workflow manually from the Actions tab.
The runner builds the amd64 image, pushes it to `ghcr.io/nissarevane/milly`, and deploys.

Let's Encrypt issues the certificate on the first request, so give it a few seconds, then:

```bash
curl -I https://milly.mondomaine.fr/up   # expect HTTP/2 200
```

### 7. Create your account

The production database starts **empty** — `db/seeds.rb` refuses to run in production, so
none of the demo data lands in your real database. Sign up at `/users/sign_up`.

> ⚠️ **Devise `:registerable` is enabled**, so anyone who finds the URL can create an
> account. For a personal balance sheet you almost certainly want to close registration
> once your account exists — remove `:registerable` from `app/models/user.rb` (and its
> route) and deploy again.

---

## Day-to-day deploys

Push to `master`. The workflow runs RSpec first and only deploys if the suite is green.

To deploy from your machine instead (slower: it cross-builds amd64 under emulation):

```bash
set -a; source .kamal/env.local; set +a
bundle exec kamal deploy
```

---

## Operations

All of these read `config/deploy.yml`, so run them from the repo with the env sourced.

```bash
bundle exec kamal console      # rails console on the VPS
bundle exec kamal logs         # tail the app logs
bundle exec kamal shell        # bash inside the running container
bundle exec kamal dbc          # psql on the production database
bundle exec kamal migrate      # run pending migrations by hand
bundle exec kamal rollback     # go back to the previous version
bundle exec kamal app details  # what is running right now
```

Migrations normally run on their own: `bin/docker-entrypoint` calls `db:prepare` every time
the container boots, before Puma starts. A migration that fails keeps the health check red,
so Kamal leaves the old version serving traffic.

---

## Backups

Postgres data lives in `/root/milly-db/data` on the VPS, but restore from a dump, not from
those files. Set up a nightly dump on the VPS:

```bash
ssh root@<VPS_IP>
mkdir -p /root/backups
crontab -e
```

```cron
0 3 * * * docker exec milly-db pg_dump -U milly -Fc milly_production > /root/backups/milly-$(date +\%F).dump 2>/root/backups/last.log
30 3 * * * find /root/backups -name 'milly-*.dump' -mtime +14 -delete
```

Pull a copy down and restore it:

```bash
scp root@<VPS_IP>:/root/backups/milly-2026-08-30.dump .

# restore into production (destructive)
cat milly-2026-08-30.dump | ssh root@<VPS_IP> \
  "docker exec -i milly-db pg_restore -U milly -d milly_production --clean --if-exists"
```

A dump on the VPS alone is not a backup — copy it off the machine regularly.

---

## Email

Devise is `:recoverable`, so password reset needs a working SMTP relay. Set
`SMTP_ADDRESS`, `SMTP_PORT` and `SMTP_USERNAME` in `env.clear` of `config/deploy.yml`, and
`SMTP_PASSWORD` as a secret. Any transactional provider works (Brevo, Mailgun, Postmark,
OVH's own SMTP).

Until that is configured, requesting a password reset raises an error
(`raise_delivery_errors` is on, deliberately — a silently dropped reset email is worse).
You can always reset a password by hand with `kamal console`:

```ruby
User.find_by(email: "moi@exemple.fr").update!(password: "un-nouveau-mot-de-passe")
```

---

## Troubleshooting

**The deploy hangs on "Waiting for the app to boot"** — the health check never went green.
Look at what the container said:

```bash
bundle exec kamal app logs --lines 100
```

Most common cause: the app cannot reach Postgres. Check that `DATABASE_HOST` in
`config/deploy.yml` matches the accessory container name (`milly-db`) and that
`POSTGRES_PASSWORD` is identical for the app and the accessory.

**No certificate / TLS errors** — `proxy.host` must resolve to the VPS, and ports 80 and
443 must be open. Let's Encrypt validates over port 80.

```bash
dig +short milly.mondomaine.fr
ssh root@<VPS_IP> "docker logs kamal-proxy --tail 50"
```

**`denied` when the VPS pulls the image** — the GHCR package is private and the token
stored on the server has expired. `GITHUB_TOKEN` is only valid for the duration of a
workflow run; if the VPS needs to pull outside a deploy, log in with a longer-lived PAT:

```bash
ssh root@<VPS_IP> "echo <PAT> | docker login ghcr.io -u nissaRevane --password-stdin"
```

**The VPS runs out of memory during a deploy** — two app containers overlap briefly.
On a 2 GB VPS, add swap:

```bash
ssh root@<VPS_IP>
fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
```

**Old images filling the disk**

```bash
bundle exec kamal prune all
```
