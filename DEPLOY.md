# Deploying Milly on an OVH VPS

Milly is deployed with [Kamal 2](https://kamal-deploy.org), the Rails 8 deployment tool.
Everything runs on the single VPS as Docker containers; GitHub Actions builds the image
and drives the deploy.

**The VPS is shared with Prunay.** Both apps sit behind the same `kamal-proxy`, which routes
on the `Host` header, so each one needs its own domain pointing at the same IP. Everything
else — app container, database, image — is per-app and named after the service. The one
thing that is genuinely shared is the proxy, which is why both repos pin the *same* Kamal
version (**2.12.0**, pinned exactly in the `Gemfile` here and in Prunay's deploy workflow):
each Kamal release requires a minimum `kamal-proxy` version, and the newer of two Kamals
refuses to deploy against a proxy the older one booted. Bump one, bump the other. See
*Troubleshooting* for what to do when they drift apart anyway.

## What ends up on the VPS

```
                       :443 / :80
                            |
                    [ kamal-proxy ]  <- terminates TLS, renews Let's Encrypt
                            |           certs, routes on the Host header
                  +---------+---------+
                  |                   |
           [ milly-web ]        [ prunay-web ]  <- Puma, RAILS_ENV=production,
                  |                   |            non-root, no published port
           [ milly-db  ]        [ prunay-db  ]  <- postgres:16-alpine
        data in /home/debian/milly-db/data
```

The database is **not** reachable from the internet: it has no published port and only
answers on the internal `kamal` Docker network.

Deploys are zero-downtime. Kamal boots the new container, waits for `/up` to return 200,
switches the proxy over, then stops the old one.

---

## Requirements

- An OVH VPS, Debian 12, reachable over SSH as `debian`. **4 GB of RAM** rather than 2:
  two apps, two Postgres, and a deploy briefly runs two app containers at once.
- A domain name with an `A` record pointing at the VPS IP — a different one from Prunay's,
  both pointing at the same address.
- Ruby 3.3.6 locally (only for the one-time bootstrap commands).

---

## One-time setup

### 1. Fill in your values

Two placeholders in [config/deploy.yml](config/deploy.yml) carry a `REMPLACER_PAR_` name,
the same convention Prunay uses:

| Key | Value |
|:---|:---|
| `REMPLACER_PAR_L_IP` — `servers.web[0]` and `accessories.db.host` | the VPS public IP, the same one Prunay uses |
| `REMPLACER_PAR_LE_HOSTNAME_OVH` — `proxy.host` and `env.clear.APP_HOST` | your domain, e.g. `milly.mondomaine.fr` |

Also set `registry.username` and `image` if you fork the repo under another account.
`image` must be **lowercase** — GHCR rejects uppercase paths.

### 2. Get SSH access to the VPS

OVH's Debian images do not open `root`: you log in as `debian`, which has passwordless
sudo. Kamal connects as that user (`ssh.user: debian` in `config/deploy.yml`) and never
needs sudo itself — `kamal server bootstrap` puts `debian` in the `docker` group, and
talking to the Docker socket is all Kamal ever does.

Two keys are used, so that revoking CI never locks you out of your own server:

| Key | Lives on | Used by |
|:---|:---|:---|
| `~/.ssh/ovh_vps` | your Mac | `ssh ovh-vps`, `kamal` run by hand |
| `~/.ssh/ovh_ci` | GitHub secret | the deploy workflows of **both** repos |

The keys are named after the machine, not the app: Prunay deploys to the same VPS with the
same pair, and a second set would only be two more things to rotate.

> Already set this up for Prunay? Skip to step 3 — the VPS, the keys and the Docker
> install are shared. Only the GitHub secrets (step 4) have to be added to this repo too.

#### a. Find out how OVH let you in

The IP is in the OVH manager under *Bare Metal Cloud → VPS*. Depending on what you chose
when ordering, the first login is either a key OVH installed for you, or a password OVH
emailed you. Probe which account answers:

```bash
for u in debian ubuntu root; do
  printf '%-8s ' "$u"
  ssh -o ConnectTimeout=5 -o BatchMode=yes "$u@<VPS_IP>" "echo works" 2>&1 | tail -1
done
```

`BatchMode=yes` makes it fail fast instead of prompting, so this only tells you about key
access. If all three fail you are on the password path — that is fine, drop `BatchMode`
and let it ask. If nothing answers at all, use the KVM console in the OVH manager.

#### b. Generate the two keys

```bash
ssh-keygen -t ed25519 -C "ovh-vps (macbook)" -f ~/.ssh/ovh_vps
ssh-keygen -t ed25519 -C "ovh-ci (github actions)" -f ~/.ssh/ovh_ci -N ""
```

The CI key **must** have an empty passphrase (`-N ""`) — no one is there to type it. Give
the laptop key a passphrase if you want; macOS stores it in the keychain.

#### c. Install both public keys for `debian`

If `debian` already answers with the key OVH installed:

```bash
ssh-copy-id -i ~/.ssh/ovh_vps.pub debian@<VPS_IP>
ssh-copy-id -i ~/.ssh/ovh_ci.pub  debian@<VPS_IP>
```

If you only have a password, same idea — it will prompt:

```bash
cat ~/.ssh/ovh_vps.pub ~/.ssh/ovh_ci.pub | ssh debian@<VPS_IP> \
  "install -d -m 700 ~/.ssh && tee -a ~/.ssh/authorized_keys >/dev/null && chmod 600 ~/.ssh/authorized_keys"
```

Check that sudo does not ask for a password, since `kamal server bootstrap` relies on it:

```bash
ssh debian@<VPS_IP> "sudo -n true && echo 'sudo ok'"
```

#### d. Add a `~/.ssh/config` entry

Listing the IP alongside the alias matters: `ssh ovh-vps` is for you, and Kamal connects
to the raw IP from `config/deploy.yml` but still reads this file, so both need to match.

```sshconfig
# VPS OVH (Milly + Prunay)
Host ovh-vps <VPS_IP>
  HostName <VPS_IP>
  User debian
  IdentityFile ~/.ssh/ovh_vps
  IdentitiesOnly yes
  AddKeysToAgent yes
  UseKeychain yes
```

Check it:

```bash
ssh ovh-vps "hostname && head -2 /etc/os-release"
```

#### e. Close the door behind you

**Keep your current session open** while you do this, and test the new one in another
terminal — a bad sshd config otherwise locks you out and you are down to the KVM console.

```bash
ssh ovh-vps
sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
# Debian cloud images override the above from a drop-in; neutralise it if present
sudo sh -c 'grep -rl PasswordAuthentication /etc/ssh/sshd_config.d/ 2>/dev/null \
  | xargs -r sed -i "s/^PasswordAuthentication.*/PasswordAuthentication no/"'
sudo sshd -t && sudo systemctl reload ssh 2>/dev/null || sudo systemctl reload sshd
```

Nothing needs root over SSH any more, so `PermitRootLogin no` is safe here — Kamal only
ever connects as `debian`. `sshd -t` validates the config before the reload, so a typo
fails loudly instead of taking SSH down.


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
| `SSH_PRIVATE_KEY` | full contents of `~/.ssh/ovh_ci` (including the BEGIN/END lines) |
| `SECRET_KEY_BASE` | from step 3 |
| `POSTGRES_PASSWORD` | from step 3 |
| `SMTP_PASSWORD` | your SMTP password (see *Email* below) |

No repository *variable* is needed: the workflow accepts the host key on first contact
(`StrictHostKeyChecking accept-new`) instead of pinning it from a `VPS_HOST` variable, so
the IP lives in `config/deploy.yml` only. Prunay's workflow does the same.

With the `gh` CLI, from the repo (it needs admin rights on `nissaRevane/Milly`):

```bash
gh secret set SSH_PRIVATE_KEY < ~/.ssh/ovh_ci
gh secret set SECRET_KEY_BASE
gh secret set POSTGRES_PASSWORD
gh secret set SMTP_PASSWORD
```

Otherwise paste them in the web UI — `pbcopy < ~/.ssh/ovh_ci` puts the private key on
your clipboard, BEGIN/END lines included.

`SECRET_KEY_BASE` and `POSTGRES_PASSWORD` are **per app**: Milly and Prunay each have their
own, even though the machine is the same. Sharing them would mean one leak costs both.

`KAMAL_REGISTRY_PASSWORD` is not needed: the workflow uses the automatic `GITHUB_TOKEN`
to push to GHCR.

### 5. Prepare the VPS

These three commands only talk to the server over SSH — no image is built locally, so they
run in seconds even from an Apple Silicon Mac.

```bash
bundle install

set -a; source .kamal/env.local; set +a   # see below
bundle exec kamal server bootstrap        # installs Docker, adds `debian` to its group
bundle exec kamal proxy boot              # starts kamal-proxy on :80/:443
bundle exec kamal accessory boot db       # starts Postgres + creates its data dir
```

`server bootstrap` adds `debian` to the `docker` group, and that only takes effect on the
next login — if the very next command fails with a permission error on the Docker socket,
run it again.

If Prunay got there first, `server bootstrap` and `proxy boot` are both no-ops: Docker is
already installed and the proxy is already running for the other app. Running them anyway
is harmless — that is exactly why both repos pin the same Kamal version, so `proxy boot`
never swaps the container out from under the app already being served.

`.kamal/env.local` is git-ignored and holds the same values you put in GitHub:

```bash
export SECRET_KEY_BASE=<from step 3>
export POSTGRES_PASSWORD=<from step 3>
export KAMAL_REGISTRY_PASSWORD=<a GitHub PAT with write:packages>
export SMTP_PASSWORD=<your SMTP password>
```

A file with `SECRET_KEY_BASE` and `POSTGRES_PASSWORD` already generated is in place; fill
in the two empty ones when you need a hand-run deploy or a working password reset.

### 6. First deploy

Push to `master`, or run the **CI & Deploy** workflow manually from the Actions tab — it
takes a `command` input, `setup` for the very first run and `deploy` afterwards, the same
two choices Prunay's workflow offers. The runner builds the amd64 image, pushes it to
`ghcr.io/nissarevane/milly`, and deploys.

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

## Hosting other people's data

Once strangers can sign up, Milly holds other people's financial position — under the
GDPR that makes you the data controller, and a few things stop being optional.

**Already in the app**

- Accounts are isolated at the model layer, not just in the controllers: a balance sheet
  line refuses an `asset_id` or `liability_id` from another account, the way
  `PropertyLinkable` already refused a foreign `property_id`. `spec/requests/account_isolation_spec.rb`
  is the regression net — add an example to it whenever a new foreign key reaches a form.
- Sign-in, sign-up and password reset are rate limited per IP (10/5 min, 5/h, 5/15 min).
  The counters live in `Milly::RATE_LIMIT_STORE`, a per-process memory cache, so the limit
  is per Puma worker. It is exact in single mode, which is how the container runs; setting
  `WEB_CONCURRENCY` above 1 would multiply it and calls for a shared store.
- `Devise.paranoid` is on, so the password-reset form no longer tells a stranger which
  addresses have an account here.
- Every user can export their whole account (`/export`) and delete it outright from
  `/mon-compte`. Deletion cascades through every association.

**Still on you**

- A privacy notice: who you are, what you store, where it is hosted, how long you keep it,
  and how to reach you. A page under `/confidentialite` is enough for a service this size.
- Backups you have actually restored once. Losing your own data is annoying; losing
  someone else's is a breach you have to report.
- A way to be reached about data — an email address that works is the minimum.
- Deciding whether you really want the registration open, or whether an invite code is a
  better fit. Public sign-up is what makes all of the above obligatory.

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

Postgres data lives in `/home/debian/milly-db/data` on the VPS, but restore from a dump,
not from those files. Set up a nightly dump on the VPS:

```bash
ssh ovh-vps
mkdir -p ~/backups
crontab -e
```

```cron
0 3 * * * docker exec milly-db pg_dump -U milly -Fc milly_production > /home/debian/backups/milly-$(date +\%F).dump 2>/home/debian/backups/milly-last.log
30 3 * * * find /home/debian/backups -name 'milly-*.dump' -mtime +14 -delete
```

Pull a copy down and restore it:

```bash
scp ovh-vps:backups/milly-2026-08-30.dump .

# restore into production (destructive)
cat milly-2026-08-30.dump | ssh ovh-vps \
  "docker exec -i milly-db pg_restore -U milly -d milly_production --clean --if-exists"
```

The dump file names are prefixed per app, so Prunay's nightly dump can land in the same
`~/backups` without either one overwriting the other.

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
ssh ovh-vps "docker logs kamal-proxy --tail 50"
```

**`denied` when the VPS pulls the image** — the GHCR package is private and the token
stored on the server has expired. `GITHUB_TOKEN` is only valid for the duration of a
workflow run; if the VPS needs to pull outside a deploy, log in with a longer-lived PAT:

```bash
ssh ovh-vps "echo <PAT> | docker login ghcr.io -u nissaRevane --password-stdin"
```

**The VPS runs out of memory during a deploy** — two app containers overlap briefly, and
with Prunay on the same machine that is four Rails processes and two Postgres at the peak.
Add swap:

```bash
ssh ovh-vps
sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

**`kamal-proxy version vX is too old, run kamal proxy reboot`** — the deploy stopped before
touching anything. There is one `kamal-proxy` container on the host, shared with Prunay, and
each Kamal release demands a minimum proxy version (2.12.0 → `v0.9.2`, 2.5.3 → `v0.8.4`).
Every `kamal deploy` checks the running container's tag first; a *newer* Kamal refuses an
*older* proxy. The reverse is fine — an older Kamal accepts a newer proxy and leaves it
alone. That is why both repos pin the same version, and why bumping Milly alone would make
this appear here rather than on Prunay's side.

Check both sides, then reboot the proxy once from the repo with the **highest** Kamal:

```bash
bundle exec kamal version                 # what this repo wants
ssh ovh-vps "docker inspect kamal-proxy --format '{{.Config.Image}}'"   # what is running
bundle exec kamal proxy reboot            # brief outage for *both* apps
```

The reboot stops, removes and re-runs the container. Routing survives it: the proxy keeps
its state in the `kamal-proxy-config` Docker volume, so Prunay's host mapping comes back on
its own — only the seconds between removal and restart are lost.

Note that a plain `kamal proxy boot` never swaps the container: it is `docker start ||
docker run`, so an already-running proxy is simply started, never replaced or downgraded.
Only `proxy reboot`, `proxy remove` and `kamal remove` can move the version — run those
from the older repo and you downgrade the proxy, which then blocks the newer one.

**Old images filling the disk** — `prune` only touches this service's own images and
containers, so it is safe to run with Prunay on the same host:

```bash
bundle exec kamal prune all
```
