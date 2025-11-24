# Stage 1: Build the server
FROM rust:1.90-slim AS server-builder

WORKDIR /build

# Install build dependencies
RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy workspace files
COPY Cargo.toml Cargo.lock ./
COPY shared ./shared
COPY server ./server
COPY client ./client

# Build the server in release mode
RUN cargo build --release -p server

# Stage 2: Build the client
FROM rust:1.90-slim AS client-builder

WORKDIR /build

# Install build dependencies including Trunk
RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install Trunk and WASM target
RUN cargo install trunk && \
    rustup target add wasm32-unknown-unknown

# Copy workspace files
COPY Cargo.toml Cargo.lock ./
COPY shared ./shared
COPY client ./client
COPY server ./server

# Build the client with Trunk
RUN cd client && trunk build --release

# Stage 3: Runtime image
FROM debian:bookworm-slim

WORKDIR /app

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    nginx \
    && rm -rf /var/lib/apt/lists/*

# Copy the built server binary
COPY --from=server-builder /build/target/release/server /app/server

# Copy the built client files
COPY --from=client-builder /build/client/dist /app/client/dist

# Create nginx configuration
RUN rm -f /etc/nginx/sites-enabled/default && \
    echo 'server {\n\
    listen 8080;\n\
    server_name _;\n\
    \n\
    root /app/client/dist;\n\
    index index.html;\n\
    \n\
    location / {\n\
    try_files $uri $uri/ /index.html;\n\
    }\n\
    \n\
    # Proxy WebSocket connections to the server\n\
    location /ws {\n\
    proxy_pass http://127.0.0.1:4001;\n\
    proxy_http_version 1.1;\n\
    proxy_set_header Upgrade $http_upgrade;\n\
    proxy_set_header Connection "upgrade";\n\
    proxy_set_header Host $host;\n\
    proxy_set_header X-Real-IP $remote_addr;\n\
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;\n\
    proxy_set_header X-Forwarded-Proto $scheme;\n\
    }\n\
    }\n\
    ' > /etc/nginx/sites-available/default && \
    ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default

# Create a startup script
RUN echo '#!/bin/bash\n\
    set -e\n\
    \n\
    # Start the server in the background\n\
    echo "[docker] starting server..."\n\
    /app/server &\n\
    SERVER_PID=$!\n\
    \n\
    # Cleanup function\n\
    cleanup() {\n\
    echo "[docker] stopping server (pid $SERVER_PID)..."\n\
    kill $SERVER_PID 2>/dev/null || true\n\
    nginx -s quit 2>/dev/null || true\n\
    exit 0\n\
    }\n\
    trap cleanup SIGTERM SIGINT EXIT\n\
    \n\
    # Wait for server to start\n\
    sleep 2\n\
    \n\
    # Start nginx\n\
    echo "[docker] starting nginx on port 8080..."\n\
    echo "[docker] Open http://localhost:8080 in your browser"\n\
    nginx -g "daemon off;" &\n\
    NGINX_PID=$!\n\
    \n\
    # Wait for either process to exit\n\
    wait -n\n\
    ' > /app/start.sh && chmod +x /app/start.sh

EXPOSE 8080 4001

CMD ["/app/start.sh"]

