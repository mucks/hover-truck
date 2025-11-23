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

# Install Trunk and wasm-bindgen-cli
# Use a recent wasm-bindgen-cli that's compatible with 0.2.x crate version
# Version 0.2.109+ should support all required intrinsics including clone_ref
ENV CARGO_BUILD_JOBS=1
RUN cargo install wasm-bindgen-cli --version 0.2.92 && \
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
# Pre-populate Trunk's wasm-bindgen cache with version 0.2.92 that supports clone_ref
# Trunk will detect 0.2.105 in Cargo.lock, but we pre-install 0.2.92 in the expected location
WORKDIR /app/client
RUN mkdir -p /root/.cache/trunk/wasm-bindgen-0.2.92 && \
    cargo install --locked wasm-bindgen-cli --version 0.2.92 && \
    cp /usr/local/cargo/bin/wasm-bindgen /root/.cache/trunk/wasm-bindgen-0.2.92/wasm-bindgen && \
    chmod +x /root/.cache/trunk/wasm-bindgen-0.2.92/wasm-bindgen
# Force Trunk to use 0.2.92 by creating a symlink from 0.2.105 to 0.2.92
RUN mkdir -p /root/.cache/trunk/wasm-bindgen-0.2.105 && \
    ln -sf /root/.cache/trunk/wasm-bindgen-0.2.92/wasm-bindgen /root/.cache/trunk/wasm-bindgen-0.2.105/wasm-bindgen
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
echo "=== Starting Hover Truck ==="\n\
echo "Checking server binary..."\n\
if [ ! -f /app/server ]; then\n\
    echo "ERROR: Server binary not found at /app/server"\n\
    exit 1\n\
fi\n\
if [ ! -x /app/server ]; then\n\
    chmod +x /app/server\n\
fi\n\
echo "Testing nginx configuration..."\n\
nginx -t || { echo "ERROR: nginx config test failed"; exit 1; }\n\
echo "Starting nginx in background..."\n\
nginx || { echo "ERROR: nginx failed to start"; cat /var/log/nginx/error.log 2>/dev/null || true; exit 1; }\n\
sleep 1\n\
echo "nginx started, proceeding to start server..."\n\
echo "Starting server on port ${PORT:-4001}..."\n\
exec /app/server\n\
' > /app/start.sh && chmod +x /app/start.sh

EXPOSE 80

CMD ["/app/start.sh"]

