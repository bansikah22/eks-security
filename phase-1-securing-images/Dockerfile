# Build stage
FROM golang:1.22-alpine AS builder

# Set the working directory
WORKDIR /app

# Copy dependency manifests and install them
COPY go.mod ./
RUN go mod download

# Copy application source code
COPY main.go .

# Build a statically linked binary
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-w -s" -o server .

# Final stage - using scratch for the absolute minimal attack surface
FROM scratch

# Use a non-root numeric user ID (e.g., 10001) for least privilege since scratch is empty
USER 10001:10001

# Copy the binary from the builder stage
COPY --from=builder --chown=10001:10001 /app/server /server

# Expose the application port
EXPOSE 8080

# Define the entrypoint
ENTRYPOINT ["/server"]
