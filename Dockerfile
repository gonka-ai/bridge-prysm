FROM golang:1.25-alpine AS builder

# Install required packages for build
RUN apk add --no-cache make gcc musl-dev linux-headers git g++ build-base cmake

WORKDIR /workspace

# Copy go.mod and go.sum first for better caching
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Build binaries
RUN CGO_ENABLED=1 GOOS=linux go build -o /usr/local/bin/beacon-chain ./cmd/beacon-chain
RUN CGO_ENABLED=1 GOOS=linux go build -o /usr/local/bin/validator ./cmd/validator

# Final stage
FROM alpine:latest

# Install runtime dependencies
RUN apk add --no-cache ca-certificates tzdata

WORKDIR /app

# Copy binaries from builder
COPY --from=builder /usr/local/bin/beacon-chain /usr/local/bin/beacon-chain
COPY --from=builder /usr/local/bin/validator /usr/local/bin/validator

# Expose ports (standard P2P and RPC ports)
EXPOSE 4000 12000 13000

ENTRYPOINT ["beacon-chain"]
