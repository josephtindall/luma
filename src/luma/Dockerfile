FROM golang:1.26-alpine AS builder
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /luma ./cmd/server

FROM alpine:3.20
RUN apk add --no-cache ca-certificates tzdata
COPY --from=builder /luma /usr/local/bin/luma
COPY migrations/ /app/migrations/
WORKDIR /app
EXPOSE 8002
ENTRYPOINT ["luma"]
