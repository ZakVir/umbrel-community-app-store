# syntax=docker/dockerfile:1
# Antigravity Server for Umbrel - multi-arch image (glibc required for language_server)
# Build: docker buildx build --platform linux/amd64,linux/arm64 -t ghcr.io/zakvir/antigravity-server:0.2.8 --push .
FROM golang:1.24-bookworm AS builder
WORKDIR /src
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates && rm -rf /var/lib/apt/lists/*
COPY . .
RUN if [ ! -f go.mod ]; then \
      echo "go.mod not found in context, cloning upstream..." && \
      rm -rf /tmp/src && \
      git clone --depth 1 https://github.com/AFSlayer/antigravity-server.git /tmp/src && \
      cp -a /tmp/src/. . && \
      echo "Cloned, ls:" && ls -la | head -20; \
    else \
      echo "Using local go.mod, ls:" && ls -la | head -20; \
    fi
# --- Patch: add AGY_DISABLE_AUTH to bypass password auth when set to 1/true ---
RUN if [ -f cmd/agy-server/run.go ]; then \
      echo "Patching run.go for AGY_DISABLE_AUTH..." && \
      awk ' \
        /publicServer := &http.Server\{Handler: authenticator.Middleware\(publicMux\)\}/ { \
            print "    publicHandler := authenticator.Middleware(publicMux)"; \
            print "    if os.Getenv(\"AGY_DISABLE_AUTH\") == \"1\" || strings.EqualFold(os.Getenv(\"AGY_DISABLE_AUTH\"), \"true\") {"; \
            print "        publicHandler = publicMux"; \
            print "    }"; \
            print "    publicServer := &http.Server{Handler: publicHandler}"; \
            next; \
        } \
        {print} \
      ' cmd/agy-server/run.go > /tmp/run.go && mv /tmp/run.go cmd/agy-server/run.go && \
      echo "Patched, verifying:" && grep -n "AGY_DISABLE_AUTH" cmd/agy-server/run.go; \
    fi
RUN go mod download
ARG TARGETOS=linux
ARG TARGETARCH
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -trimpath -ldflags="-s -w -X main.version=0.2.8" -o /out/agy-server ./cmd/agy-server && \
    chmod +x /out/agy-server && \
    /out/agy-server version

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates wget curl bash tar gzip procps iptables iproute2 dnsutils netcat-openbsd \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd -g 1000 agy && useradd -u 1000 -g 1000 -m -d /home/agy agy \
    && mkdir -p /data/agy-home /data/workspace /home/agy/.gemini \
    && chown -R 1000:1000 /data /home/agy
COPY --from=builder /out/agy-server /usr/local/bin/agy-server
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY egress.sh /usr/local/bin/egress.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/egress.sh /usr/local/bin/agy-server
USER 1000:1000
ENV HOME=/home/agy \
    AGY_HOME=/data/agy-home \
    AGY_WORKSPACE_ROOT=/data/workspace \
    AGY_PORT=8765 \
    AGY_BIND=0.0.0.0 \
    AGY_LANGUAGE_SERVER=/data/agy-home/language_server \
    AGY_DISABLE_AUTH=true
EXPOSE 8765
VOLUME ["/data/agy-home", "/data/workspace", "/home/agy/.gemini"]
HEALTHCHECK --interval=30s --timeout=10s --retries=3 --start-period=180s CMD wget -q --spider http://127.0.0.1:8765/__agy/login || wget -q --spider http://127.0.0.1:8765/ || exit 1
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["serve"]
