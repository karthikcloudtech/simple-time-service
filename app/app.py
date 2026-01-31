from flask import Flask, request, jsonify
from datetime import datetime
import logging
import os
import socket
import platform
import atexit
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
from opentelemetry import trace
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.instrumentation.requests import RequestsInstrumentor
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource
from kafka_producer import get_producer
from kafka_consumer import get_consumer
from kafka_config import log_kafka_config

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Get hostname and OS
hostname = socket.gethostname()
host_os = platform.system()

def get_pod_ip():
    """Get the pod IP address (Kubernetes environment)"""
    # Method 1: Check environment variable (if set in deployment)
    pod_ip = os.getenv('POD_IP') or os.getenv('HOST_IP')
    if pod_ip:
        return pod_ip
    
    # Method 2: Get IP from hostname resolution
    try:
        pod_ip = socket.gethostbyname(hostname)
        # Filter out localhost
        if pod_ip and pod_ip != '127.0.0.1' and not pod_ip.startswith('127.'):
            return pod_ip
    except (socket.gaierror, socket.herror):
        pass
    
    # Method 3: Get IP from network interfaces (non-localhost)
    try:
        # Connect to external address to determine local IP
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.settimeout(0)
        try:
            # Doesn't actually connect, just determines local IP
            s.connect(('8.8.8.8', 80))
            pod_ip = s.getsockname()[0]
            if pod_ip and pod_ip != '127.0.0.1':
                return pod_ip
        except Exception:
            pass
        finally:
            s.close()
    except Exception:
        pass
    
    return None

# Get pod IP at startup
pod_ip = get_pod_ip()

# Initialize OpenTelemetry
resource = Resource.create({"service.name": "simple-time-service"})
trace.set_tracer_provider(TracerProvider(resource=resource))
tracer = trace.get_tracer(__name__)

# Configure OTLP exporter (for OpenTelemetry Collector)
otlp_exporter = OTLPSpanExporter(
    endpoint=os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://otel-collector:4317"),
    insecure=True
)
span_processor = BatchSpanProcessor(otlp_exporter)
trace.get_tracer_provider().add_span_processor(span_processor)

app = Flask(__name__)

# Instrument Flask and Requests
FlaskInstrumentor().instrument_app(app)
RequestsInstrumentor().instrument()

# Initialize Kafka
log_kafka_config()
kafka_producer = get_producer()
kafka_consumer = get_consumer()

# Register example event handlers for consumer
def handle_http_request(event_data):
    """Handle incoming HTTP request events"""
    logger.info(f"Consumer received HTTP request event: {event_data}")

def handle_http_response(event_data):
    """Handle outgoing HTTP response events"""
    logger.info(f"Consumer received HTTP response event: {event_data}")

def handle_error(event_data):
    """Handle error events"""
    logger.warning(f"Consumer received error event: {event_data}")

kafka_consumer.register_handler('http_request', handle_http_request)
kafka_consumer.register_handler('http_response', handle_http_response)
kafka_consumer.register_handler('error', handle_error)

# Start consumer in background
kafka_consumer.start()

# Register cleanup on exit
def cleanup_kafka():
    """Clean up Kafka resources on exit"""
    kafka_consumer.stop()
    kafka_producer.flush()
    kafka_producer.close()

atexit.register(cleanup_kafka)

# Prometheus metrics
REQUEST_COUNT = Counter(
    'http_requests_total',
    'Total HTTP requests',
    ['method', 'endpoint', 'status']
)

REQUEST_DURATION = Histogram(
    'http_request_duration_seconds',
    'HTTP request duration',
    ['method', 'endpoint']
)

@app.route("/healthz", methods=["GET"])
def health_check():
    """Lightweight health check endpoint for Kubernetes probes"""
    REQUEST_COUNT.labels(method='GET', endpoint='/healthz', status='200').inc()
    return jsonify({"status": "healthy"}), 200

@app.route("/metrics", methods=["GET"])
def metrics():
    """Prometheus metrics endpoint"""
    return generate_latest(), 200, {'Content-Type': CONTENT_TYPE_LATEST}

@app.route("/kafka/publish", methods=["POST"])
def kafka_publish():
    """Publish a custom event to Kafka"""
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "No JSON data provided"}), 400
        
        event_type = data.get('event_type', 'custom_event')
        event_data = data.get('data', {})
        topic = data.get('topic', None)
        
        success = kafka_producer.send_event(
            event_type=event_type,
            data=event_data,
            topic=topic
        )
        
        if success:
            return jsonify({
                "status": "success",
                "message": f"Event '{event_type}' published to Kafka",
                "event": {"event_type": event_type, "data": event_data}
            }), 200
        else:
            return jsonify({
                "status": "error",
                "message": "Failed to publish event to Kafka"
            }), 500
            
    except Exception as e:
        logger.error(f"Error publishing to Kafka: {str(e)}", exc_info=True)
        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500

@app.route("/kafka/status", methods=["GET"])
def kafka_status():
    """Get Kafka status and configuration"""
    try:
        producer_status = "connected" if kafka_producer.producer else "disconnected"
        consumer_status = "running" if kafka_consumer.is_running else "stopped"
        
        return jsonify({
            "kafka_producer": producer_status,
            "kafka_consumer": consumer_status,
            "consumer_topics": kafka_consumer.topics,
            "consumer_handlers": list(kafka_consumer.message_handlers.keys())
        }), 200
    except Exception as e:
        logger.error(f"Error getting Kafka status: {str(e)}", exc_info=True)
        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500

@app.route("/kafka/flush", methods=["POST"])
def kafka_flush():
    """Flush pending messages in Kafka producer"""
    try:
        kafka_producer.flush()
        return jsonify({
            "status": "success",
            "message": "Kafka producer flushed"
        }), 200
    except Exception as e:
        logger.error(f"Error flushing Kafka producer: {str(e)}", exc_info=True)
        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500

@app.route("/", methods=["GET"])
def get_time_and_ip():
    with REQUEST_DURATION.labels(method='GET', endpoint='/').time():
        with tracer.start_as_current_span("get_time_and_ip") as span:
            try:
                forwarded_for_list = request.headers.getlist("X-Forwarded-For")

                if forwarded_for_list:
                    all_ips = [ip.strip() for ip in forwarded_for_list[0].split(",") if ip.strip()]
                    user_ip = all_ips[0] if all_ips else request.remote_addr
                else:
                    all_ips = []
                    user_ip = request.remote_addr

                # Send request event to Kafka
                kafka_producer.send_request_event(
                    user_ip=user_ip,
                    method='GET',
                    endpoint='/',
                    hostname=hostname,
                    os=host_os
                )

                response = {
                    "timestamp": datetime.utcnow().isoformat() + "Z",
                    "user_ip": user_ip,
                    "proxy_chain": all_ips if all_ips else "No proxy IPs found",
                    "hostname": hostname,
                    "os": host_os,
                    "pod_ip": pod_ip
                }
                
                span.set_attribute("user_ip", user_ip)
                span.set_attribute("has_proxy_chain", len(all_ips) > 0)
                
                logger.info(f"Request from {user_ip}", extra={"user_ip": user_ip, "proxy_chain": all_ips})
                
                # Send response event to Kafka
                kafka_producer.send_response_event(
                    user_ip=user_ip,
                    status_code=200,
                    response_time_ms=0  # Would be actual response time in production
                )
                
                REQUEST_COUNT.labels(method='GET', endpoint='/', status='200').inc()
                return jsonify(response), 200
            except Exception as e:
                logger.error(f"Error processing request: {str(e)}", exc_info=True)
                span.record_exception(e)
                
                # Send error event to Kafka
                kafka_producer.send_error_event(
                    error_message=str(e),
                    error_type='request_processing_error',
                    endpoint='/'
                )
                
                REQUEST_COUNT.labels(method='GET', endpoint='/', status='500').inc()
                return jsonify({"error": "Internal server error"}), 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)  # nosemgrep: python.flask.security.audit.app-run-param-config.avoid_app_run_with_bad_host
