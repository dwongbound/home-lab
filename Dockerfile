# The home-lab page as one small container for jarvis.
# Stage 1 builds the page; stage 2 keeps only the built page and the server,
# which uses nothing but Node's own modules, so no node_modules ship.
FROM node:22-bookworm-slim AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM node:22-bookworm-slim
WORKDIR /app
ENV NODE_ENV=production \
    # Port 80 inside the container (see docker-compose.yml for why).
    PORT=80 \
    # No systemd inside a container, so Jarvis's status comes from its port.
    JARVIS_UNIT= \
    # WSL's GPU libraries, mounted from the PC, so nvidia-smi can run here.
    LD_LIBRARY_PATH=/usr/lib/wsl/lib
COPY package.json ./
COPY server ./server
COPY --from=build /app/dist ./dist
# Ask the snapshot API every 30 s; Docker marks the container unhealthy if
# the server stops answering.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
  CMD node -e "fetch('http://127.0.0.1:'+process.env.PORT+'/api/snapshot').then(r=>process.exit(r.ok?0:1),()=>process.exit(1))"
CMD ["node", "server/index.mjs"]
