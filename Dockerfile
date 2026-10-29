FROM debian:bookworm-slim AS build
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git unzip xz-utils libglu1-mesa nodejs \
    && rm -rf /var/lib/apt/lists/*
ARG FLUTTER_VERSION=3.27.2
RUN git clone --depth 1 --branch ${FLUTTER_VERSION} https://github.com/flutter/flutter.git /opt/flutter
ENV PATH="/opt/flutter/bin:${PATH}"
RUN git config --global --add safe.directory /opt/flutter && flutter config --enable-web --no-analytics
WORKDIR /app
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get
COPY lib ./lib
COPY web ./web
COPY scripts/optimize-web.js ./scripts/optimize-web.js
ARG API_BASE_URL=/api
RUN flutter build web --release --no-web-resources-cdn --dart-define=API_BASE_URL=${API_BASE_URL} \
    && node scripts/optimize-web.js build/web

FROM node:22-bookworm-slim
WORKDIR /app
ENV NODE_ENV=production PORT=10000 STATIC_DIR=/app/web
COPY --from=build --chown=node:node /app/build/web ./web
COPY --chown=node:node server ./server
USER node
EXPOSE 10000
CMD ["node", "server/mock-server.js"]
