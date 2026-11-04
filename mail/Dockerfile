FROM node:22-alpine
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force
COPY server.js ./
COPY public ./public
ENV PORT=8095 MAIL_DATA=/data NODE_ENV=production
USER node
EXPOSE 8095
CMD ["node", "server.js"]
