# syntax=docker/dockerfile:1
# Build: docker build --build-context lostcoords-ui=../lostcoords-ui -t twitter-crm .
# The lostcoords-ui gem is pinned to a commit of the sibling checkout; only its git history is copied in.
ARG RUBY_VERSION=4.0.2
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base
WORKDIR /rails
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 libyaml-0-2 sqlite3 && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    APP_DATA_DIR="/data" \
    LD_PRELOAD="libjemalloc.so.2"

FROM base AS build
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives
COPY --from=lostcoords-ui .git /lostcoords-ui/.git
COPY Gemfile Gemfile.lock ./
# The lockfile records the sibling's host path. Re-resolving inside the image only rewrites that git source;
# every gem version stays as locked. The adjusted lockfile is kept over the host copy below.
RUN BUNDLE_DEPLOYMENT=0 BUNDLE_FROZEN=0 bundle install && \
    cp Gemfile.lock /tmp/Gemfile.lock && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git
COPY . .
RUN cp /tmp/Gemfile.lock Gemfile.lock && bundle check
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile

FROM base
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    mkdir -p /data && chown rails:rails /data
COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=rails:rails --from=build /rails /rails
USER 1000:1000
VOLUME /data
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s CMD curl -fsS http://localhost:3000/up || exit 1
ENTRYPOINT ["/rails/bin/docker-entrypoint"]
CMD ["./bin/rails", "server", "-b", "0.0.0.0", "-p", "3000"]
