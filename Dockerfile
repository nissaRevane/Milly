# syntax=docker/dockerfile:1
#
# Trois cibles :
#   development  -> utilisee par docker-compose (gems de dev/test, code monte en volume)
#   production   -> cible par defaut, celle que Kamal construit et pousse sur le VPS
#
# Voir DEPLOY.md pour le deploiement.

ARG RUBY_VERSION=3.3.6

# ---------------------------------------------------------------- base commune
FROM ruby:${RUBY_VERSION}-slim AS base

WORKDIR /app

# libpq5 = client Postgres au runtime, jemalloc = moins de fragmentation memoire
# (utile sur un petit VPS), postgresql-client = pg_isready / psql / pg_dump.
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      curl \
      libjemalloc2 \
      libpq5 \
      postgresql-client \
      tzdata && \
    rm -rf /var/lib/apt/lists/*

ENV LD_PRELOAD="libjemalloc.so.2" \
    RUBY_YJIT_ENABLE="1" \
    BUNDLE_PATH="/usr/local/bundle"

# ------------------------------------------------- outils de compilation natifs
FROM base AS build

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential \
      git \
      libpq-dev \
      pkg-config && \
    rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------- image de dev
FROM build AS development

ENV RAILS_ENV="development"

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .
RUN chmod +x bin/* && \
    bundle exec bootsnap precompile --gemfile app/ lib/

ENTRYPOINT ["./bin/docker-entrypoint"]
EXPOSE 3000
CMD ["./bin/rails", "server", "-b", "0.0.0.0"]

# --------------------------------- gems de prod + precompilation des assets
FROM build AS prod-build

ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_WITHOUT="development:test"

COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git

COPY . .
RUN chmod +x bin/* && \
    bundle exec bootsnap precompile --gemfile app/ lib/

# SECRET_KEY_BASE_DUMMY evite d'avoir besoin du vrai secret au moment du build.
RUN SECRET_KEY_BASE_DUMMY=1 bundle exec rails assets:precompile

# ------------------------------------------------- image finale (production)
FROM base AS production

ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_WITHOUT="development:test"

COPY --from=prod-build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=prod-build /app /app

# Puma ne tourne pas en root : seuls les repertoires reellement ecrits en prod
# appartiennent a l'utilisateur applicatif.
RUN mkdir -p log storage tmp/pids tmp/cache && \
    groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    chown -R rails:rails db log storage tmp
USER 1000:1000

ENTRYPOINT ["./bin/docker-entrypoint"]
EXPOSE 3000
CMD ["./bin/rails", "server"]
