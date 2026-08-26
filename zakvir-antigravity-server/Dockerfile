# syntax=docker/dockerfile:1
# Antigravity Server for Umbrel - multi-arch image
# Build: docker buildx build --platform linux/amd64,linux/arm64 -t ghcr.io/zakvir/antigravity-server:0.2.7 --push .
FROM golang:1.24-alpine AS builder
WORKDIR /src
# Install git for go mod download
RUN apk add --no-cache git ca-certificates
# Copy source - in CI we clone from GitHub; for local build copy context
COPY . .
# Alternative for Umbrel store build context: clone directly if no local source
# Use robust copy that includes hidden files and doesn't rely on glob expansion
RUN if [ ! -f go.mod ]; then \
      echo "go.mod not found in context, cloning upstream..." && \
      rm -rf /tmp/src && \
      git clone --depth 1 https://github.com/AFSlayer/antigravity-server.git /tmp/src && \
      cp -a /tmp/src/. . && \
      echo "Cloned, ls:" && ls -la | head -20; \
    else \
      echo "Using local go.mod, ls:" && ls -la | head -20; \
    fi
RUN go mod download
ARG TARGETOS=linux
ARG TARGETARCH
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -trimpath -ldflags="-s -w -X main.version=0.2.7" -o /out/agy-server ./cmd/agy-server && \
    chmod +x /out/agy-server && \
    /out/agy-server version

FROM alpine:3.20
RUN apk add --no-cache ca-certificates wget curl bash tar gzip procps
# Create umbrel user (1000:1000)
RUN addgroup -g 1000 agy && adduser -D -u 1000 -G agy agy -h /home/agy && \
    mkdir -p /data/agy-home /data/workspace /home/agy/.gemini && \
    chown -R 1000:1000 /data /home/agy
COPY --from=builder /out/agy-server /usr/local/bin/agy-server
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/agy-server
USER 1000:1000
ENV HOME=/home/agy \
    AGY_HOME=/data/agy-home \
    AGY_WORKSPACE_ROOT=/data/workspace \
    AGY_PORT=8765 \
    AGY_BIND=0.0.0.0 \
    AGY_LANGUAGE_SERVER=/data/agy-home/language_server
EXPOSE 8765
VOLUME ["/data/agy-home", "/data/workspace", "/home/agy/.gemini"]
HEALTHCHECK --interval=30s --timeout=10s --retries=3 --start-period=60s CMD wget -q --spider http://127.0.0.1:8765/__agy/login || exit 1
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["serve"]
