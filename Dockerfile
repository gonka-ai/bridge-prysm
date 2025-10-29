FROM golang:1.24-alpine AS prysm-builder

# Install required packages
RUN apk add --no-cache make gcc musl-dev linux-headers git g++ build-base cmake

# Set working directory
WORKDIR /workspace

# Copy go.mod and go.sum first for better caching
COPY go.mod go.sum ./

# Download dependencies first
RUN go mod download

# Copy source code
COPY . .

# Now build directly to final locations
RUN CGO_ENABLED=1 GOOS=linux go build -o /usr/local/bin/beacon-chain ./cmd/beacon-chain
RUN CGO_ENABLED=1 GOOS=linux go build -o /usr/local/bin/validator ./cmd/validator

# Make binaries executable
RUN chmod +x /usr/local/bin/beacon-chain /usr/local/bin/validator

ENTRYPOINT ["beacon-chain"]
