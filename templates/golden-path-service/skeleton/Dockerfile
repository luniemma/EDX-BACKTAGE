FROM node:22-bookworm-slim

WORKDIR /app

# No lockfile ships in the skeleton, so this is `npm install` rather than
# `npm ci`. Commit the lockfile your first build produces and switch to
# `npm ci --omit=dev` — until you do, builds are not reproducible.
COPY package.json ./
RUN npm install --omit=dev

COPY . .

# The chart runs this with readOnlyRootFilesystem and runAsUser 1000, which is
# the `node` user in this image. Anything that needs to write at runtime needs
# an emptyDir volume in the chart.
USER node

EXPOSE 8080
CMD ["node", "index.js"]
