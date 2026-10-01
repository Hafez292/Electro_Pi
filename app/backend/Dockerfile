FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production

FROM node:20-alpine
WORKDIR /app
# Run as non-root user for security
USER node
# Copy built node_modules and application code with proper permissions
COPY --chown=node:node --from=builder /app/node_modules ./node_modules
COPY --chown=node:node . .
EXPOSE 5000
CMD ["node", "server.js"]