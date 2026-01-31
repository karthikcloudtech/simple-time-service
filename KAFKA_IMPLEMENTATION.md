# Kafka Implementation Guide

This document describes the Kafka producer and consumer implementation for the simple-time-service.

## Overview

The simple-time-service now includes:
- **Kafka Producer**: Sends events (requests, responses, errors) to Kafka topics
- **Kafka Consumer**: Consumes and processes events from Kafka topics
- **Metrics**: Prometheus metrics for producer and consumer operations
- **REST Endpoints**: For testing and managing Kafka operations

## Architecture

### Components

1. **kafka_config.py**: Configuration and constants
   - Broker configuration
   - Topic definitions
   - Consumer group settings
   - Shared Kafka client config

2. **kafka_producer.py**: KafkaProducerService
   - Singleton pattern for single producer instance
   - Methods for sending different event types
   - Prometheus metrics integration
   - Error handling and callbacks

3. **kafka_consumer.py**: KafkaConsumerService
   - Threaded consumer for background message processing
   - Event handler registration system
   - Lag tracking and metrics
   - Graceful startup/shutdown

4. **app.py**: Flask integration
   - Producer and consumer initialization
   - Event publishing on HTTP requests/responses
   - REST endpoints for Kafka management
   - Graceful cleanup on exit

## Configuration

### Environment Variables

```bash
# Kafka brokers (comma-separated)
KAFKA_BROKERS=localhost:9092

# Topics
KAFKA_TOPIC_EVENTS=simple-time-service-events
KAFKA_TOPIC_REQUESTS=simple-time-service-requests

# Consumer group
KAFKA_CONSUMER_GROUP=simple-time-service-group

# Auto offset reset behavior
KAFKA_AUTO_OFFSET_RESET=earliest
```

### Default Values

- **Brokers**: `localhost:9092`
- **Events Topic**: `simple-time-service-events`
- **Requests Topic**: `simple-time-service-requests`
- **Consumer Group**: `simple-time-service-group`

## Usage

### Producer

#### Basic Event Publishing

```python
from kafka_producer import get_producer

producer = get_producer()

# Send custom event
producer.send_event(
    event_type='user_signup',
    data={'user_id': '123', 'email': 'user@example.com'},
    topic='my-topic',
    key='123'  # Optional: for partitioning
)
```

#### Pre-built Event Methods

```python
# Send request event
producer.send_request_event(
    user_ip='192.168.1.1',
    method='GET',
    endpoint='/',
    hostname='pod-1'
)

# Send response event
producer.send_response_event(
    user_ip='192.168.1.1',
    status_code=200,
    response_time_ms=45.5
)

# Send error event
producer.send_error_event(
    error_message='Database connection failed',
    error_type='database_error',
    service='auth-service'
)
```

#### Flush and Close

```python
# Flush pending messages
producer.flush(timeout_ms=10000)

# Close connection
producer.close()
```

### Consumer

#### Starting Consumer

```python
from kafka_consumer import get_consumer

consumer = get_consumer()

# Start consuming in background thread
consumer.start()
```

#### Registering Event Handlers

```python
def handle_requests(event_data):
    print(f"Received request: {event_data}")

def handle_responses(event_data):
    print(f"Received response: {event_data}")

consumer.register_handler('http_request', handle_requests)
consumer.register_handler('http_response', handle_responses)
```

#### Stopping Consumer

```python
consumer.stop()  # Stops the background thread and closes connection
```

## REST Endpoints

### Health Check
```
GET /healthz
```
Response: `{"status": "healthy"}`

### Main Endpoint (with Kafka events)
```
GET /
```
Response includes timestamp, user IP, proxy chain, pod info, and automatically publishes events to Kafka.

### Kafka Status
```
GET /kafka/status
```
Response:
```json
{
  "kafka_producer": "connected",
  "kafka_consumer": "running",
  "consumer_topics": ["simple-time-service-events", "simple-time-service-requests"],
  "consumer_handlers": ["http_request", "http_response", "error"]
}
```

### Publish Event
```
POST /kafka/publish
Content-Type: application/json

{
  "event_type": "custom_event",
  "data": {
    "user_id": "123",
    "action": "login"
  },
  "topic": "simple-time-service-events"
}
```

Response:
```json
{
  "status": "success",
  "message": "Event 'custom_event' published to Kafka",
  "event": {
    "event_type": "custom_event",
    "data": {"user_id": "123", "action": "login"}
  }
}
```

### Flush Producer
```
POST /kafka/flush
```
Response: `{"status": "success", "message": "Kafka producer flushed"}`

### Metrics Endpoint
```
GET /metrics
```
Returns Prometheus metrics in text format, including:
- `kafka_messages_sent_total`
- `kafka_message_size_bytes`
- `kafka_messages_received_total`
- `kafka_message_process_time_seconds`
- `kafka_consumer_lag_ms`

## Metrics

### Producer Metrics

- `kafka_messages_sent_total[topic, status]`: Counter
  - Counts successful and failed message sends
- `kafka_message_size_bytes[topic]`: Histogram
  - Tracks size of sent messages

### Consumer Metrics

- `kafka_messages_received_total[topic, event_type, status]`: Counter
  - Counts received and processed messages
- `kafka_message_process_time_seconds[topic, event_type]`: Histogram
  - Tracks time to process each message
- `kafka_consumer_lag_ms[topic]`: Histogram
  - Tracks consumer lag

## Event Schema

### Request Event
```json
{
  "timestamp": "2026-01-31T12:34:56.789Z",
  "event_type": "http_request",
  "data": {
    "user_ip": "192.168.1.1",
    "method": "GET",
    "endpoint": "/",
    "hostname": "pod-1",
    "os": "Linux"
  }
}
```

### Response Event
```json
{
  "timestamp": "2026-01-31T12:34:56.789Z",
  "event_type": "http_response",
  "data": {
    "user_ip": "192.168.1.1",
    "status_code": 200,
    "response_time_ms": 45.5
  }
}
```

### Error Event
```json
{
  "timestamp": "2026-01-31T12:34:56.789Z",
  "event_type": "error",
  "data": {
    "error_message": "Database connection failed",
    "error_type": "database_error",
    "service": "auth-service"
  }
}
```

## Setup for Kubernetes

### Docker Build

The Dockerfile already includes Kafka dependencies (kafka-python is in requirements.txt).

```bash
docker build -t simple-time-service:latest .
```

### Kubernetes Deployment

Update your deployment YAML to include Kafka broker configuration:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: simple-time-service
spec:
  template:
    spec:
      containers:
      - name: app
        image: simple-time-service:latest
        env:
        - name: KAFKA_BROKERS
          value: "kafka-broker-1:9092,kafka-broker-2:9092,kafka-broker-3:9092"
        - name: KAFKA_TOPIC_EVENTS
          value: "simple-time-service-events"
        - name: KAFKA_TOPIC_REQUESTS
          value: "simple-time-service-requests"
        - name: KAFKA_CONSUMER_GROUP
          value: "simple-time-service-group"
```

### Kafka Cluster Prerequisites

Ensure the following Kafka topics exist:

```bash
# Create topics using kafka-topics tool
kafka-topics --create --topic simple-time-service-events \
  --bootstrap-server kafka-broker:9092 \
  --partitions 3 \
  --replication-factor 2

kafka-topics --create --topic simple-time-service-requests \
  --bootstrap-server kafka-broker:9092 \
  --partitions 3 \
  --replication-factor 2
```

## Local Development

### Start Kafka Locally

Using Docker Compose:

```bash
docker-compose up -d kafka zookeeper
```

Or use Confluent's Docker images:

```bash
docker run -d --name zookeeper \
  -e ZOOKEEPER_CLIENT_PORT=2181 \
  confluentinc/cp-zookeeper:latest

docker run -d --name kafka \
  -e KAFKA_BROKER_ID=1 \
  -e KAFKA_ZOOKEEPER_CONNECT=zookeeper:2181 \
  -e KAFKA_ADVERTISED_LISTENERS=PLAINTEXT://kafka:9092 \
  -e KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR=1 \
  confluentinc/cp-kafka:latest
```

### Test Producer

```bash
curl -X POST http://localhost:8080/kafka/publish \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "test_event",
    "data": {"test": "data"}
  }'
```

### Test Consumer

Consumer automatically starts and processes events. Check logs:

```bash
docker logs -f simple-time-service
```

### Check Kafka Status

```bash
curl http://localhost:8080/kafka/status
```

## Best Practices

1. **Error Handling**: Always wrap Kafka operations in try-except blocks
2. **Graceful Shutdown**: Use `atexit.register()` to ensure clean shutdown
3. **Keys for Ordering**: Use user_ip or user_id as message key to maintain per-user ordering
4. **Metrics**: Monitor producer/consumer metrics regularly
5. **Consumer Handlers**: Register handlers before starting the consumer
6. **Batch Processing**: Use `auto_commit_interval_ms` for efficient offset management
7. **Monitoring**: Track consumer lag to detect processing bottlenecks

## Troubleshooting

### Connection Issues

```python
# Check if producer is connected
if kafka_producer.producer:
    print("Producer is connected")
else:
    print("Producer failed to initialize")
```

### Consumer Not Processing Messages

- Verify consumer is started: `consumer.start()`
- Check handlers are registered: `consumer.message_handlers`
- Verify topics exist and have messages
- Check consumer lag metrics

### Memory Leaks

- Always call `producer.close()` and `consumer.stop()`
- Use `atexit.register()` for automatic cleanup
- Monitor memory usage in Kubernetes

### Performance Tuning

Adjust these in `kafka_config.py`:
- `max_in_flight_requests_per_connection`: For throughput
- `batch_size`: For latency vs throughput trade-off
- `linger_ms`: For batching delay
- `max_poll_records`: For consumer processing batch size

## References

- [kafka-python Documentation](https://kafka-python.readthedocs.io/)
- [Apache Kafka Documentation](https://kafka.apache.org/documentation/)
- [Prometheus Metrics Best Practices](https://prometheus.io/docs/practices/instrumentation/)
