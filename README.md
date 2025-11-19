## Hover Truck - Bevy + Rust WebSocket Multiplayer

### Development

Run the server:

```bash
cargo run -p server
```

Run the client (native):

```bash
cargo run -p client
```

Run the client (web via Trunk):

```bash
cargo install trunk
cd client
trunk serve --open
```

### Docker Deployment

#### Using Docker Compose (Recommended for local testing)

```bash
docker-compose up --build
```

Or run in detached mode:

```bash
docker-compose up -d --build
```

Stop the container:

```bash
docker-compose down
```

#### Using Docker directly

Build the Docker image:

```bash
docker build -t hover-truck .
```

Run the container:

```bash
docker run -p 80:80 hover-truck
```

The container serves both the client and server:
- Client: http://localhost/
- WebSocket: ws://localhost/ws

### GitHub Container Registry

The project includes a GitHub Action that automatically builds and pushes Docker images to GHCR on pushes to main.

Pull and run the latest image:

```bash
docker pull ghcr.io/YOUR_USERNAME/hover-truck:latest
docker run -p 80:80 ghcr.io/YOUR_USERNAME/hover-truck:latest
```

Or use a specific tag:

```bash
docker pull ghcr.io/YOUR_USERNAME/hover-truck:main
docker run -p 80:80 ghcr.io/YOUR_USERNAME/hover-truck:main
```

### Notes

- Default server URL is `ws://127.0.0.1:4001/ws`. On web, you can pass `?server=ws://host:port/ws`.
- Controls: A/Left = turn left, D/Right = turn right, W/Up = straight.
- Goal: collect items to grow your hover truck; cut other players off (collision = death).

