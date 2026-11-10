# Multi-stage Dockerfile cho NestJS Backend Gateway
# Repo dùng bun.lock (package-lock.json bị gitignore) → cài dependency bằng Bun, chạy bằng Node.

# 1. Cài toàn bộ dependency (kể cả dev) để build
FROM oven/bun:1.4-alpine AS deps
WORKDIR /app
COPY package.json bun.lock ./
RUN bun install --frozen-lockfile

# 2. Build TypeScript → dist/
FROM node:22-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN node node_modules/@nestjs/cli/bin/nest.js build

# 3. Chỉ cài dependency production
FROM oven/bun:1.4-alpine AS prod-deps
WORKDIR /app
COPY package.json bun.lock ./
RUN bun install --frozen-lockfile --production

# 4. Image chạy production
FROM node:22-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
COPY package.json ./
COPY --from=prod-deps /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
USER node
EXPOSE 8000
CMD ["node", "dist/main.js"]
