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

# This stage deliberately runs as root. It is discarded — only the runtime
# stage below ships, and that one drops to the unprivileged `node` user.
# Building as `node` instead means every directory COPY has to create along the
# way is still owned by root, and `yarn build:backend` dies with
# "EACCES: permission denied, mkdir '/app/packages/backend/dist'".
WORKDIR /app
ENV YARN_ENABLE_GLOBAL_CACHE=false

# Yarn 4 comes from the checked-in release in .yarn/releases via corepack.
COPY .yarn ./.yarn
COPY .yarnrc.yml package.json yarn.lock backstage.json ./
COPY packages/app/package.json packages/app/
COPY packages/backend/package.json packages/backend/

# --immutable: fail rather than silently drift from the committed lockfile.
RUN yarn install --immutable

COPY . .

RUN yarn tsc \
 && yarn build:backend --config ../../app-config.yaml

########## Runtime stage ##########
FROM node:22-bookworm-slim AS runtime

ENV PYTHON=/usr/bin/python3
RUN apt-get update && apt-get install -y --no-install-recommends \
      python3 python3-pip python3-venv g++ build-essential libsqlite3-dev ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# TechDocs generation is a Python toolchain: Backstage shells out to `mkdocs`.
# With `techdocs.generator.runIn: docker` the backend would try to start a
# container instead, and there is no Docker daemon inside this pod — so docs
# builds fail at runtime, not at deploy time. Installing mkdocs here is what
# makes `runIn: local` work.
#
# A virtualenv rather than a plain `pip install`: Debian bookworm enforces
# PEP 668, so installing into the system interpreter fails with
# "externally-managed-environment". The alternative, --break-system-packages,
# does exactly what it says to a shared interpreter.
#
# Pin for reproducible builds:  docker build --build-arg TECHDOCS_CORE_VERSION=1.5.1 .
ARG TECHDOCS_CORE_VERSION=
RUN python3 -m venv /opt/techdocs \
 && /opt/techdocs/bin/pip install --no-cache-dir --upgrade pip \
 && /opt/techdocs/bin/pip install --no-cache-dir \
      "mkdocs-techdocs-core${TECHDOCS_CORE_VERSION:+==${TECHDOCS_CORE_VERSION}}" \
 && /opt/techdocs/bin/mkdocs --version

# Puts `mkdocs` on PATH for the backend process, which invokes it by name.
ENV PATH="/opt/techdocs/bin:${PATH}"

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
# Software templates are registered as file locations in app-config, so they
# must exist inside the image or the catalog logs a missing-location error.
COPY --from=build --chown=node:node /app/templates ./templates

EXPOSE 7007

# app-config.production.yaml is layered on top and reads its values from env
# (POSTGRES_*, APP_BASE_URL, ...) — see deploy/helm/backstage/values.yaml.
CMD ["node", "packages/backend", "--config", "app-config.yaml", "--config", "app-config.production.yaml"]
