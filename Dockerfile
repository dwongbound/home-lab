# The server in one image. It only uses Node's built-ins, so there is
# nothing to install or build.
FROM node:22-slim
WORKDIR /app
ENV NODE_ENV=production
COPY package.json ./
COPY server ./server
CMD ["node", "server/index.mjs"]
