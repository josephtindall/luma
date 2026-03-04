# ── Build stage ───────────────────────────────────────────────────────────────
FROM golang:1.26-alpine AS builder

WORKDIR /app

# Cache dependency downloads separately from source compilation.
COPY go.mod go.sum ./
RUN go mod download

COPY . .

# CGO disabled for a fully static binary; no libc dependency in the runtime image.
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -o luma-auth ./cmd/server
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -o luma-auth-admin ./cmd/admin

# ── Runtime stage ─────────────────────────────────────────────────────────────
FROM alpine:3.20

# ca-certificates: needed for outbound TLS (future integrations).
# tzdata: needed for IANA timezone validation.
RUN apk add --no-cache ca-certificates tzdata && \
    addgroup -S auth && adduser -S auth -G auth

WORKDIR /app
COPY --from=builder /app/luma-auth /app/luma-auth-admin ./

USER auth
EXPOSE 8080

ENTRYPOINT ["./luma-auth"]
