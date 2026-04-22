# Canvas LMS on Klutch — production image
# Mirrors the Klutch Canvas LMS guide: clones instructure/canvas-lms,
# installs Ruby + Yarn deps, precompiles assets, runs Puma on port 3000.

FROM ruby:3.3-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    RAILS_ENV=production \
    NODE_MAJOR=20 \
    BUNDLE_PATH=/usr/local/bundle \
    APP_HOME=/app

# System deps
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential git curl gnupg ca-certificates \
      libxmlsec1-dev libxslt1-dev libpq-dev \
      libsqlite3-dev zlib1g-dev libidn11-dev \
      python3 make g++ \
      postgresql-client redis-tools \
      imagemagick libmagickwand-dev \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
       | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
       > /etc/apt/sources.list.d/nodesource.list \
    && apt-get update && apt-get install -y --no-install-recommends nodejs \
    && npm install -g yarn \
    && rm -rf /var/lib/apt/lists/*

# Clone Canvas LMS stable
WORKDIR ${APP_HOME}
ARG CANVAS_BRANCH=stable
RUN git clone --depth 1 --branch ${CANVAS_BRANCH} https://github.com/instructure/canvas-lms.git ${APP_HOME}

# Ruby deps
RUN gem install bundler -v 2.5.11 \
 && bundle config set --local without 'development test' \
 && bundle install --jobs 4 --retry 3

# JS deps
RUN yarn install --pure-lockfile

# Drop in our config templates (database, redis, mail, domain)
COPY config/database.yml      ${APP_HOME}/config/database.yml
COPY config/redis.yml         ${APP_HOME}/config/redis.yml
COPY config/outgoing_mail.yml ${APP_HOME}/config/outgoing_mail.yml
COPY config/domain.yml        ${APP_HOME}/config/domain.yml

# Entrypoint
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Volume for uploads + compiled assets (mount 100GB on Klutch here)
VOLUME ["/app/public/assets"]

EXPOSE 3000

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb", "-b", "tcp://0.0.0.0:3000"]
