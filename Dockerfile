# The page and its server in one image. Built in two steps so the running
# image has no node_modules at all: the server only uses Node's built-ins.
FROM node:22-slim AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
# Which build this is, shown in the page's footer. The image has no .git, so
# the deploy passes them in (README, "In Docker"); without them it says 'dev'.
ARG GIT_SHA=dev
ARG BUILT_AT=
RUN GIT_SHA="$GIT_SHA" BUILT_AT="$BUILT_AT" npm run build

FROM node:22-slim
WORKDIR /app
ENV NODE_ENV=production
COPY package.json ./
COPY server ./server
COPY --from=build /app/dist ./dist
CMD ["node", "server/index.mjs"]
