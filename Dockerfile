# Production image: the Go server serving the API and the built web app (one origin).
# Build context: the repository root.

FROM debian:trixie-slim AS web
ARG FLUTTER_VERSION=3.50.0
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl git unzip xz-utils \
    && rm -rf /var/lib/apt/lists/* \
    && git clone --depth 1 --branch $FLUTTER_VERSION https://github.com/flutter/flutter.git /flutter
ENV PATH=/flutter/bin:$PATH
RUN flutter config --no-analytics --enable-web && flutter precache --web
WORKDIR /app
COPY app/pubspec.yaml app/pubspec.lock ./
RUN flutter pub get
COPY app/ ./
RUN flutter build web --release

FROM golang:1.26 AS server
WORKDIR /src
COPY server/go.mod server/go.sum ./
RUN go mod download
COPY server/ ./
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /oikoboard ./cmd/oikoboard

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=server /oikoboard /oikoboard
COPY --from=web /app/build/web /web
ENV OIKO_ADDR=:8090 OIKO_WEB_DIR=/web
EXPOSE 8090
ENTRYPOINT ["/oikoboard"]
