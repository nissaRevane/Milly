FROM ruby:3.3.6-slim

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    build-essential \
    libpq-dev \
    nodejs \
    curl \
    git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile ./
COPY Gemfile.lock ./
RUN bundle lock --add-platform x86_64-linux && bundle install

COPY . .

RUN bundle exec bootsnap precompile --gemfile app/ lib/

COPY bin/docker-entrypoint /usr/bin/docker-entrypoint
RUN chmod +x /usr/bin/docker-entrypoint

ENTRYPOINT ["docker-entrypoint"]

EXPOSE 3000

CMD ["rails", "server", "-b", "0.0.0.0"]
