# Multi-stage build for the Backstage backend.
#
# Backstage ships a host-build Dockerfile at packages/backend/Dockerfile which
# expects `yarn build:backend` to have run first. That does not suit CI doing a
# plain `docker build`, so this is the self-contained multi-stage variant
# documented at https://backstage.io/docs/deployment/docker#multi-stage-build
#
# Build from the repo root:  docker build -t backstage .

########## Build stage ##########
FROM node:22-bookworm-slim AS build

# node-gyp needs python3; isolated-vm (used by the scaffolder) needs a C++
# toolchain; better-sqlite3 needs libsqlite3-dev.
ENV PYTHON=/usr/bin/python3
RUN apt-get update && apt-get install -y --no-install-recommends \
      python3 g++ build-essential libsqlite3-dev ca-certificates \
    && rm -rf /var/lib/apt/lists/*

USER node
WORKDIR /app
ENV YARN_ENABLE_GLOBAL_CACHE=false

# Yarn 4 comes from the checked-in release in .yarn/releases via corepack.
COPY --chown=node:node .yarn ./.yarn
COPY --chown=node:node .yarnrc.yml package.json yarn.lock backstage.json ./
COPY --chown=node:node packages/app/package.json packages/app/package.json
COPY --chown=node:node packages/backend/package.json packages/backend/package.json

# --immutable: fail rather than silently drift from the committed lockfile.
RUN yarn install --immutable

COPY --chown=node:node . .

RUN yarn tsc \
 && yarn build:backend --config ../../app-config.yaml

########## Runtime stage ##########
FROM node:22-bookworm-slim AS runtime

ENV PYTHON=/usr/bin/python3
RUN apt-get update && apt-get install -y --no-install-recommends \
      python3 g++ build-essential libsqlite3-dev ca-certificates \
    && rm -rf /var/lib/apt/lists/*

USER node
WORKDIR /app

ENV NODE_ENV=production
# Required for the scaffolder's isolated-vm to work on Node 20+.
ENV NODE_OPTIONS="--no-node-snapshot"
ENV YARN_ENABLE_GLOBAL_CACHE=false

COPY --from=build --chown=node:node /app/.yarn ./.yarn
COPY --from=build --chown=node:node /app/.yarnrc.yml /app/backstage.json ./

# The skeleton is just the per-package package.json files — copying it before
# the bundle keeps `yarn install` cached across source-only changes.
COPY --from=build --chown=node:node /app/yarn.lock /app/package.json /app/packages/backend/dist/skeleton.tar.gz ./
RUN tar xzf skeleton.tar.gz && rm skeleton.tar.gz

RUN yarn workspaces focus --all --production && rm -rf "$(yarn cache clean)"

COPY --from=build --chown=node:node /app/packages/backend/dist/bundle.tar.gz ./
RUN tar xzf bundle.tar.gz && rm bundle.tar.gz

COPY --from=build --chown=node:node /app/app-config*.yaml ./
COPY --from=build --chown=node:node /app/examples ./examples

EXPOSE 7007

# app-config.production.yaml is layered on top and reads its values from env
# (POSTGRES_*, APP_BASE_URL, ...) — see deploy/helm/backstage/values.yaml.
CMD ["node", "packages/backend", "--config", "app-config.yaml", "--config", "app-config.production.yaml"]
