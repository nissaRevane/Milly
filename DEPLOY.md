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

### 2. Get SSH access to the VPS

Kamal drives the whole deployment over SSH as `root`, so root must accept a key. Two keys
are used, so that revoking CI never locks you out of your own server:

| Key | Lives on | Used by |
|:---|:---|:---|
| `~/.ssh/milly_vps` | your Mac | `ssh milly-vps`, `kamal` run by hand |
| `~/.ssh/milly_ci` | GitHub secret | the deploy workflow |

#### a. Find out how OVH let you in

The IP is in the OVH manager under *Bare Metal Cloud → VPS*. Depending on what you chose
when ordering, the first login is either a key OVH installed for you, or a root password
OVH emailed you. Probe which account answers:

```bash
for u in root ubuntu debian; do
  printf '%-8s ' "$u"
  ssh -o ConnectTimeout=5 -o BatchMode=yes "$u@<VPS_IP>" "echo works" 2>&1 | tail -1
done
```

`BatchMode=yes` makes it fail fast instead of prompting, so this only tells you about key
access. If all three fail you are on the password path — that is fine, drop `BatchMode`
and let it ask. If nothing answers at all, use the KVM console in the OVH manager.

#### b. Generate the two keys

```bash
ssh-keygen -t ed25519 -C "milly-vps (macbook)" -f ~/.ssh/milly_vps
ssh-keygen -t ed25519 -C "milly-ci (github actions)" -f ~/.ssh/milly_ci -N ""
```

The CI key **must** have an empty passphrase (`-N ""`) — no one is there to type it. Give
the laptop key a passphrase if you want; macOS stores it in the keychain.

#### c. Install both public keys for root

If root already answers (OVH installed your order key):

```bash
ssh-copy-id -i ~/.ssh/milly_vps.pub root@<VPS_IP>
ssh-copy-id -i ~/.ssh/milly_ci.pub  root@<VPS_IP>
```

If only `ubuntu` / `debian` answers, root has no key yet — push both through sudo:

```bash
cat ~/.ssh/milly_vps.pub ~/.ssh/milly_ci.pub | ssh ubuntu@<VPS_IP> \
  "sudo install -d -m 700 /root/.ssh && sudo tee -a /root/.ssh/authorized_keys >/dev/null \
   && sudo chmod 600 /root/.ssh/authorized_keys"
```

If you only have the root password, same idea without sudo (it will prompt):

```bash
cat ~/.ssh/milly_vps.pub ~/.ssh/milly_ci.pub | ssh root@<VPS_IP> \
  "install -d -m 700 ~/.ssh && tee -a ~/.ssh/authorized_keys >/dev/null && chmod 600 ~/.ssh/authorized_keys"
```

#### d. Add a `~/.ssh/config` entry

Listing the IP alongside the alias matters: `ssh milly-vps` is for you, and Kamal connects
to the raw IP from `config/deploy.yml` but still reads this file, so both need to match.

```sshconfig
# Milly production VPS (OVH)
Host milly-vps <VPS_IP>
  HostName <VPS_IP>
  User root
  IdentityFile ~/.ssh/milly_vps
  IdentitiesOnly yes
  AddKeysToAgent yes
  UseKeychain yes
```

Check it:

```bash
ssh milly-vps "hostname && head -2 /etc/os-release"
```

#### e. Close the door behind you

**Keep your current session open** while you do this, and test the new one in another
terminal — a bad sshd config otherwise locks you out and you are down to the KVM console.

```bash
ssh milly-vps
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
# Ubuntu cloud images override the above from a drop-in; neutralise it if present
grep -rl PasswordAuthentication /etc/ssh/sshd_config.d/ 2>/dev/null \
  | xargs -r sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/'
sshd -t && systemctl reload ssh 2>/dev/null || systemctl reload sshd
```

`prohibit-password` keeps root reachable by key (which Kamal needs) while refusing
passwords. `sshd -t` validates the config before the reload, so a typo fails loudly
instead of taking SSH down.

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
| `SSH_PRIVATE_KEY` | full contents of `~/.ssh/milly_ci` (including the BEGIN/END lines) |
| `SECRET_KEY_BASE` | from step 3 |
| `POSTGRES_PASSWORD` | from step 3 |
| `SMTP_PASSWORD` | your SMTP password (see *Email* below) |

**Variables**

| Name | Value |
|:---|:---|
| `VPS_HOST` | the VPS public IP — used to pin the host key before deploying |

With the `gh` CLI, from the repo (it needs admin rights on `nissaRevane/Milly`):

```bash
gh secret set SSH_PRIVATE_KEY < ~/.ssh/milly_ci
gh secret set SECRET_KEY_BASE
gh secret set POSTGRES_PASSWORD
gh variable set VPS_HOST --body "<VPS_IP>"
```

Otherwise paste them in the web UI — `pbcopy < ~/.ssh/milly_ci` puts the private key on
your clipboard, BEGIN/END lines included.

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
