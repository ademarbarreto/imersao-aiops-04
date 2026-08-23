FROM node:20-bookworm-slim

WORKDIR /app

COPY --chown=node:node package.json package-lock.json ./

RUN npm ci --omit=dev

COPY --chown=node:node . .

USER node

EXPOSE 8080

HEALTHCHECK --interval=15s --timeout=5s --start-period=20s --retries=3 \
    CMD ["node", "-e", "require('http').get('http://127.0.0.1:8080/health', r => process.exit(r.statusCode === 200 ? 0 : 1)).on('error', () => process.exit(1))"]

CMD ["node", "server.js"]
