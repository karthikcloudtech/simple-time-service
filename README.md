# Simple Time Service

A production-ready Flask microservice that demonstrates graceful degradation for optional services (Kafka, OpenTelemetry, Prometheus). The app always works, but some features are skipped if dependencies are unavailable.

**Documentation:**
- 📖 **[ARCHITECTURE.md](ARCHITECTURE.md)** - Complete system design, data flow, deployment architecture
- 🚀 **[QUICK_START.md](QUICK_START.md)** - Local development & setup instructions
- 📋 **README.md (this file)** - Features, endpoints, configuration

## What This Service Does

1. **Returns request metadata** - timestamp, user IP, proxy chain, hostname, OS, pod IP
2. **Sends events to Kafka** - HTTP requests, responses, and errors  
3. **Persists events to SQLite** - Kafka consumer writes events to database
4. **Provides observability** - Health checks, Prometheus metrics, OpenTelemetry tracing (all optional)

## Quick Demo

```bash
# Run locally (no dependencies needed)
python3 app/app.py

# Test
curl http://localhost:8080/
```

Response:
```json
{
  "message": "Hello, Kafka is UP",
  "timestamp": "2026-02-03T10:30:45.123456Z",
  "user_ip": "192.168.1.100",
  "kafka_status": "UP"
}
```

## How It Works

**The app always serves requests**, but with optional features:

| Service | Status | Behavior |
|---------|--------|----------|
| **Core App** | ✅ Required | Always works |
| **Kafka** | Optional | Events sent to message queue (async) |
| **Database** | Optional | Kafka consumer persists events to SQLite |
| **OpenTelemetry** | Optional | Distributed tracing |
| **Prometheus** | Optional | Metrics collection |

If Kafka is down → app keeps working, events aren't sent  
If Database is down → events still sent to Kafka, just not stored  
If both down → app still 100% functional

## Project Structure

```
app/
  ├── app.py                  # Flask application (370 lines)
  ├── kafka_config.py         # Kafka configuration (17 lines)
  ├── kafka_producer.py       # Event producer (89 lines)
  ├── kafka_consumer.py       # Event consumer, DB writer (95 lines)
  └── database.py             # SQLite persistence layer
Dockerfile                    # Multi-stage Docker build
requirements.txt              # Python dependencies
docs/infrastructure/          # Deployment & infrastructure guides
```

## Technology Stack

- **Application:** Flask 3.1.2 (Python 3.11)
- **Events:** Kafka (optional)
- **Database:** SQLite (optional)
- **Observability:** Prometheus + OpenTelemetry (optional)
- **Container:** Docker (multi-stage build)
- **Orchestration:** Kubernetes (EKS)
- **Infrastructure:** Terraform
- **Cloud:** AWS

## Core Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/` | GET | Main endpoint - returns timestamp and network info |
| `/healthz` | GET | Kubernetes liveness probe |
| `/metrics` | GET | Prometheus metrics |
| `/kafka/status` | GET | Check Kafka service status |
| `/kafka/publish` | POST | Publish custom event to Kafka |
| `/kafka/flush` | POST | Flush pending Kafka messages |

## Configuration

### Environment Variables

```bash
# Flask
FLASK_ENV=production
FLASK_DEBUG=0

# Kafka (Optional - auto-detected)
KAFKA_BROKERS=localhost:9092
KAFKA_TOPIC_EVENTS=simple-time-events
KAFKA_CONSUMER_GROUP=simple-time-group

# Database (Optional)
DB_PATH=/tmp/events.db

# OpenTelemetry (Optional)
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317

# Kubernetes
POD_IP=10.0.0.5
HOST_IP=10.0.0.5
```

## Event-Driven Database Persistence

Events flow through Kafka to a background consumer that persists them to SQLite:

```
HTTP Request
    ↓
Kafka Producer (send_request_event, send_response_event, send_error_event)
    ↓
Kafka Topic (simple-time-events)
    ↓
Kafka Consumer (background thread)
    ↓
SQLite Database (http_requests, http_responses, errors tables)
```

### Database Schema

**http_requests table:**
- user_ip, method, endpoint, hostname, os, timestamp

**http_responses table:**
- user_ip, status_code, response_time_ms, timestamp

**errors table:**
- error_message, error_type, endpoint, timestamp

## Resilience & Graceful Degradation

All optional services are wrapped in try-except blocks:

```python
# Kafka initialization
try:
    kafka_producer = get_producer()
except:
    kafka_producer = None  # Continue without Kafka

# Per-request Kafka calls
if kafka_producer:
    try:
        kafka_producer.send_request_event(...)
    except:
        logger.warning("Kafka send failed")  # Continue anyway
```

This ensures:
- ✅ App never crashes due to missing dependencies
- ✅ All requests return 200 OK (core functionality always works)
- ✅ Services gracefully degrade when dependencies are unavailable
- ✅ Logs show which services failed to initialize

## Getting Started

### Local Development

```bash
# Install dependencies
pip install -r requirements.txt

# Run without optional services (instant)
python3 app/app.py

# Test in another terminal
curl http://localhost:8080/
```

### With Docker

```bash
docker build -t simple-time-service .
docker run -p 8080:8080 simple-time-service
curl http://localhost:8080/
```

### With Kubernetes

See [docs/infrastructure/SETUP.md](docs/infrastructure/SETUP.md) for EKS deployment.

## Troubleshooting

### App won't start?
```bash
python3 -m py_compile app/*.py  # Check syntax
```

### Kafka not working?
```bash
curl http://localhost:8080/kafka/status
```
Shows `kafka_status: "NOT UP"` if broker unavailable. That's expected - app still works.

### Database not writing?
Check `/tmp/events.db` exists and is writable. Consumer logs will show warnings if writes fail, but app continues.

## Infrastructure & Deployment

For production deployment, Kubernetes setup, monitoring, and infrastructure guides, see:

- **[docs/infrastructure/SETUP.md](docs/infrastructure/SETUP.md)** - EKS cluster setup
- **[docs/infrastructure/MONITORING_ACCESS.md](docs/infrastructure/MONITORING_ACCESS.md)** - Prometheus, Grafana, Kibana access
- **[docs/infrastructure/DNS_SETUP.md](docs/infrastructure/DNS_SETUP.md)** - DNS configuration
- **[docs/infrastructure/SECRETS_MANAGEMENT.md](docs/infrastructure/SECRETS_MANAGEMENT.md)** - Secrets setup
- **[docs/infrastructure/PROJECT_STRUCTURE.md](docs/infrastructure/PROJECT_STRUCTURE.md)** - Full project layout
- **[docs/infrastructure/TROUBLESHOOTING_AWS_LB_CONTROLLER.md](docs/infrastructure/TROUBLESHOOTING_AWS_LB_CONTROLLER.md)** - Troubleshooting
- **[docs/infrastructure/IAM_ROLE_ANNOTATION_FIX.md](docs/infrastructure/IAM_ROLE_ANNOTATION_FIX.md)** - IAM fixes

## Simplification & Code Quality

**Kafka Code Simplified by 60%:**
- kafka_config.py: 63 → 17 lines  
- kafka_producer.py: 186 → 89 lines
- kafka_consumer.py: 210 → 95 lines
- **Total:** ~500 → 201 lines (no functionality lost)

**Removed complexity:**
- Complex singleton patterns
- Prometheus Kafka metrics
- Message lag tracking
- Batch configuration
- Callback support

**What remains:**
- Core producer/consumer functionality
- Event sending (request, response, error)
- Thread-safe message processing
- Graceful error handling

## Tech Decisions

**Why Kafka for events?**
- ✅ Decoupling: Producer doesn't wait for DB writes
- ✅ Scalability: Multiple consumers can process events
- ✅ Durability: Event replay capability
- ✅ Async processing: Non-blocking event persistence

**Why not just log?**
- ❌ Logs are ephemeral (rotated/deleted)
- ❌ Hard to query specific events
- ❌ Not suitable for analytics
- ✅ SQLite database provides permanent, queryable event store

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────┐
│                   Client Requests                       │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
        ┌────────────────────────────┐
        │   Flask App (Port 8080)    │
        │  • /healthz (health check) │
        │  • / (main endpoint)       │
        │  • /metrics (Prometheus)   │
        │  • /kafka/* (Kafka ops)    │
        └────────────────────────────┘
                     │
         ┌───────────┼───────────┐
         ▼           ▼           ▼
    Kafka Msg    OpenTelemetry  Prometheus
    (Optional)    (Optional)     (Optional)
         │
         ▼
    ┌──────────────────────┐
    │ Kafka Topic          │
    │ (simple-time-events) │
    └──────────────────────┘
         │
         ▼
    ┌─────────────────────────┐
    │ Kafka Consumer          │
    │ (Background Thread)     │
    └─────────────────────────┘
         │
         ▼
    ┌──────────────────────────┐
    │ SQLite Database          │
    │ • http_requests          │
    │ • http_responses         │
    │ • errors                 │
    └──────────────────────────┘
```

## Contributing

To modify the service:

1. Edit files in `app/`
2. Test locally: `python3 app/app.py`
3. Verify syntax: `python3 -m py_compile app/*.py`
4. Build Docker: `docker build -t simple-time-service .`
5. Push changes and let CI/CD handle deployment

## License

Production deployment uses AWS infrastructure. See [docs/infrastructure/](docs/infrastructure/) for deployment details.

---

## Quick Start

**For daily practice (destroy/recreate workflow):**
- See [SETUP.md](SETUP.md) for setup instructions
- See [INSTALLATION_BEST_PRACTICES.md](INSTALLATION_BEST_PRACTICES.md) for detailed best practices

**TL;DR:**
```bash
