# Multi-stage build for hover-truck

# Stage 1: Build server
FROM rust:1.90-slim AS server-builder

WORKDIR /app

# Install dependencies for building
RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy only Cargo files first for better caching
COPY Cargo.toml Cargo.lock ./
COPY shared/Cargo.toml ./shared/
COPY server/Cargo.toml ./server/
COPY client/Cargo.toml ./client/

# Create dummy source files to build dependencies only
RUN mkdir -p shared/src server/src client/src && \
    echo "fn main() {}" > server/src/main.rs && \
    echo "fn main() {}" > client/src/main.rs && \
    echo "pub fn dummy() {}" > shared/src/lib.rs

# Build dependencies (this layer will be cached if Cargo files don't change)
ENV CARGO_BUILD_JOBS=2
RUN cargo build --release -p server

# Now copy actual source code (overwrites dummy files)
COPY shared ./shared
COPY server ./server
# Also copy client to satisfy workspace (even though we don't build it in this stage)
COPY client ./client

# Rebuild server with actual source (only rebuilds if source changed)
RUN cargo build --release -p server

# Stage 2: Build WASM client
FROM rust:1.90-slim AS client-builder

WORKDIR /app

# Install dependencies for building
RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install wasm32 target and build tools (cache this layer)
RUN rustup target add wasm32-unknown-unknown

# Install Trunk and wasm-bindgen-cli (cache this layer if versions don't change)
ENV CARGO_BUILD_JOBS=1
RUN cargo install --locked wasm-bindgen-cli && \
    cargo install --locked trunk

# Copy only Cargo files first for better caching
COPY Cargo.toml Cargo.lock ./
COPY shared/Cargo.toml ./shared/
COPY client/Cargo.toml ./client/
COPY server/Cargo.toml ./server/

# Create dummy source files to build dependencies only
RUN mkdir -p shared/src client/src server/src && \
    echo "fn main() {}" > client/src/main.rs && \
    echo "fn main() {}" > server/src/main.rs && \
    echo "pub fn dummy() {}" > shared/src/lib.rs

# Build dependencies (this layer will be cached if Cargo files don't change)
RUN cargo build --release --target wasm32-unknown-unknown -p client

# Now copy actual source code (overwrites dummy files)
COPY shared ./shared
COPY client ./client
COPY server ./server

# Rebuild client with actual source (only rebuilds if source changed)
WORKDIR /app/client
RUN trunk build --release

# Stage 3: Runtime image
FROM debian:bookworm-slim

WORKDIR /app

# Install nginx and wget (for healthcheck)
RUN apt-get update && apt-get install -y \
    nginx \
    ca-certificates \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Copy server binary
COPY --from=server-builder /app/target/release/server /app/server

# Copy client static files
COPY --from=client-builder /app/client/dist /usr/share/nginx/html

# Copy nginx configuration
COPY nginx.conf /etc/nginx/nginx.conf

# Create startup script
RUN echo '#!/bin/bash\n\
set -e\n\
# Start nginx in background\n\
nginx\n\
# Start server in foreground\n\
exec /app/server\n\
' > /app/start.sh && chmod +x /app/start.sh

EXPOSE 80

CMD ["/app/start.sh"]

