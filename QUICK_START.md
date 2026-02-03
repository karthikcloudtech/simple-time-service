# Quick Start Guide

A production-ready Flask microservice that demonstrates graceful degradation for optional services (Kafka, OpenTelemetry, Prometheus). The app always works, but some features are skipped if dependencies are unavailable.

## What This Service Does

1. **Returns request metadata** - timestamp, user IP, proxy chain, hostname, OS, pod IP
2. **Sends events to Kafka** - HTTP requests, responses, and errors
3. **Persists events to SQLite** - Kafka consumer writes events to database
4. **Provides observability** - Health checks, Prometheus metrics, OpenTelemetry tracing (all optional)

## How It Works (Simple Explanation)

**The app always serves requests**, but with optional features:

| Service | Status | Behavior |
|---------|--------|----------|
| **Core App** | Required | Always works, returns timestamp and IP info |
| **Kafka** | Optional | Events sent to message queue (fire-and-forget) |
| **Database** | Optional | Kafka consumer persists events to SQLite |
| **OpenTelemetry** | Optional | Distributed tracing (useful for debugging) |
| **Prometheus** | Optional | Metrics collection for monitoring |

If Kafka is down → app keeps working, events just aren't sent  
If Database is down → events still sent to Kafka, just not stored  
If both are down → app still 100% functional, metrics show `kafka_status: NOT UP`

## Project Structure

```
app/
  ├── app.py                  # Main Flask application (370 lines)
  ├── kafka_config.py         # Kafka configuration (17 lines)
  ├── kafka_producer.py       # Kafka producer (89 lines)
  ├── kafka_consumer.py       # Kafka consumer (95 lines) - writes to DB
  └── database.py             # SQLite persistence layer
Dockerfile                    # Multi-stage Docker build
requirements.txt              # Python dependencies
```

## Running Locally

### Option 1: Without Optional Services (Fast)
```bash
cd /Users/karthik/workspace/simple-time-service
python3 app/app.py
```

App automatically handles missing Kafka, OpenTelemetry, and Prometheus gracefully.

Then test:
```bash
curl http://localhost:8080/healthz
curl http://localhost:8080/
```

### Option 2: With Docker (Isolated)
```bash
docker build -t simple-time-service .
docker run -p 8080:8080 simple-time-service
```

### Option 3: Full Stack with docker-compose
```bash
docker-compose -f docker-compose.dev.yml up
```

## Key Features

### Core Endpoints
- `GET /healthz` - Health check
- `GET /` - Returns timestamp, IP, hostname, OS
- `GET /metrics` - Prometheus metrics
- `POST /kafka/publish` - Publish custom event
- `GET /kafka/status` - Kafka status
- `POST /kafka/flush` - Flush Kafka messages

### Error Handling
✓ **OpenTelemetry**: Fails gracefully if collector unavailable  
✓ **Kafka**: Fails gracefully if broker unavailable  
✓ **Prometheus**: Fails gracefully if metrics unavailable  
✓ All core endpoints work without optional services  

### Response Example
```json
{
  "message": "Hello, Kafka is UP",
  "timestamp": "2026-02-03T10:30:45.123456Z",
  "user_ip": "192.168.1.100",
  "proxy_chain": "203.0.113.45, 198.51.100.23",
  "hostname": "app-pod-123",
  "os": "Linux",
  "pod_ip": "10.0.0.5",
  "kafka_status": "UP"
}
```

If Kafka is unavailable, `kafka_status` will be `"NOT UP"` but the request still succeeds with 200 OK.

## Configuration

### Environment Variables
```bash
# Flask
FLASK_ENV=production          # Default: not set
FLASK_DEBUG=0                 # Default: 0

# OpenTelemetry (Optional)
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317

# Kafka (Optional)
KAFKA_BROKERS=localhost:9092
KAFKA_TOPIC_EVENTS=simple-time-events
KAFKA_CONSUMER_GROUP=simple-time-group

# Database (Optional)
DB_PATH=/tmp/events.db        # SQLite database file location

# Pod Info (Kubernetes)
POD_IP=10.0.0.5              # For pod IP detection
HOST_IP=10.0.0.5
```

## Event-Driven Database Persistence

### Architecture
Kafka → Consumer → SQLite Database

### When Kafka + Database Available ✅
- HTTP requests sent to Kafka
- Consumer automatically persists events to SQLite
- Custom event publishing supported
- Full event audit trail in database

### When Kafka Down ⚠️
- App logs warnings and continues
- HTTP requests still return 200 OK
- Events not persisted (fire-and-forget)
- Response shows `"kafka_status": "NOT UP"`

### When Database Down ⚠️
- Kafka events produced normally
- Consumer fails to persist with warnings
- App continues serving requests
- Graceful degradation

### When Both Down ✓
- App still fully functional
- Returns `kafka_status: "NOT UP"`
- No events persisted, but service available

## Health Checks

### Liveness Probe
```bash
curl http://localhost:8080/healthz
# Returns: {"status": "healthy"} 200 OK
```

### Readiness Check
```bash
# Core app always ready
curl http://localhost:8080/
# Returns: timestamp, IPs, hostname (200 OK)
```

## Simplification Changes

**Kafka Code Reduced:**
- kafka_config.py: 63 lines → 17 lines (73% reduction)
- kafka_producer.py: 186 lines → 89 lines (52% reduction)
- kafka_consumer.py: 210 lines → 95 lines (55% reduction)
- **Total**: ~500 lines → 201 lines (60% reduction)

**What's Removed (for simplicity):**
- Prometheus Kafka metrics
- Complex singleton patterns
- Message lag tracking
- Callback support
- Batch configuration

**What's Kept (core features):**
- Producer/consumer functionality
- Event sending (request, response, error)
- Thread-safe message processing
- Environment configuration
- Graceful error handling

## Troubleshooting

### App won't start
Check logs for import errors. The app handles missing dependencies gracefully.

```bash
python3 -m py_compile app/*.py  # Syntax check
```

### Kafka not working
Check KAFKA_BROKERS environment variable:
```bash
curl http://localhost:8080/kafka/status
# Should return 503 if Kafka unavailable, or status details if available
```

### OpenTelemetry not working
Check OTEL_EXPORTER_OTLP_ENDPOINT environment variable. App logs warnings and continues.

## Files

### Core Application
- ✓ app.py - Comprehensive error handling, Kafka status in response
- ✓ kafka_config.py - Simplified configuration
- ✓ kafka_producer.py - Simplified producer
- ✓ kafka_consumer.py - Consumer persists events to database
- ✓ database.py - SQLite persistence layer (3 tables: http_requests, http_responses, errors)
- ✓ Dockerfile - Multi-stage build (verified)
