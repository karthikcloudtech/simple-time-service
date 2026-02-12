from flask import Flask, request, jsonify, render_template_string
from datetime import datetime
import logging
import os
import socket
import platform
import atexit
from contextlib import ExitStack
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
from database import init_db


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

# Initialize OpenTelemetry (with graceful degradation)
tracer = None
try:
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
    logger.info("OpenTelemetry initialized successfully")
except Exception as e:
    logger.warning(f"OpenTelemetry initialization failed: {str(e)}. Continuing without tracing.")
    tracer = None

app = Flask(__name__)

# Instrument Flask and Requests (with graceful degradation)
try:
    FlaskInstrumentor().instrument_app(app)
    RequestsInstrumentor().instrument()
    logger.info("Flask and Requests instrumented")
except Exception as e:
    logger.warning(f"Failed to instrument Flask/Requests: {str(e)}")

# Initialize database
try:
    init_db()
    logger.info("Database initialized successfully")
except Exception as e:
    logger.warning(f"Database init failed: {str(e)}")

# Initialize Kafka (with graceful degradation)
kafka_producer = None
kafka_consumer = None

try:
    log_kafka_config()
    kafka_producer = get_producer()
    kafka_consumer = get_consumer()
    
    # Start consumer in background (events persist to database automatically)
    kafka_consumer.start()
    logger.info("Kafka initialized successfully")
    
except Exception as e:
    logger.warning(f"Kafka initialization failed: {str(e)}. Continuing without Kafka support.")
    kafka_producer = None
    kafka_consumer = None

# Register cleanup on exit
def cleanup_kafka():
    """Clean up Kafka resources on exit"""
    try:
        if kafka_consumer:
            kafka_consumer.stop()
        if kafka_producer:
            kafka_producer.flush()
            kafka_producer.close()
    except Exception as e:
        logger.error(f"Error during Kafka cleanup: {str(e)}")

atexit.register(cleanup_kafka)

# Prometheus metrics (with graceful degradation)
REQUEST_COUNT = None
REQUEST_DURATION = None

try:
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
    logger.info("Prometheus metrics initialized")
except Exception as e:
    logger.warning(f"Prometheus metrics initialization failed: {str(e)}")
    REQUEST_COUNT = None
    REQUEST_DURATION = None

# HTML Status Dashboard Template
STATUS_DASHBOARD = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Simple Time Service - Status Dashboard</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
        }
        
        .container {
            max-width: 900px;
            width: 100%;
            background: white;
            border-radius: 20px;
            box-shadow: 0 20px 60px rgba(0, 0, 0, 0.3);
            overflow: hidden;
        }
        
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 40px;
            text-align: center;
        }
        
        .header h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
            font-weight: 700;
        }
        
        .status-badge {
            display: inline-block;
            padding: 8px 16px;
            background: rgba(255, 255, 255, 0.2);
            border-radius: 20px;
            font-size: 0.9em;
            font-weight: 600;
        }
        
        .healthy {
            background: #4CAF50;
        }
        
        .content {
            padding: 40px;
        }
        
        .info-grid {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 30px;
            margin-bottom: 40px;
        }
        
        @media (max-width: 600px) {
            .info-grid {
                grid-template-columns: 1fr;
            }
        }
        
        .info-item {
            border-left: 4px solid #667eea;
            padding-left: 16px;
        }
        
        .info-label {
            font-size: 0.85em;
            color: #999;
            text-transform: uppercase;
            letter-spacing: 0.5px;
            margin-bottom: 4px;
            font-weight: 600;
        }
        
        .info-value {
            font-size: 1.1em;
            color: #333;
            word-break: break-all;
            font-family: 'Monaco', 'Courier New', monospace;
            background: #f5f5f5;
            padding: 8px 12px;
            border-radius: 4px;
        }
        
        .dependencies {
            background: #f9f9f9;
            border-radius: 12px;
            padding: 24px;
            margin-bottom: 30px;
        }
        
        .dependencies h3 {
            color: #333;
            margin-bottom: 16px;
            font-size: 1.2em;
        }
        
        .dep-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
            gap: 16px;
        }
        
        .dep-item {
            background: white;
            border: 2px solid #e0e0e0;
            border-radius: 8px;
            padding: 16px;
            text-align: center;
            transition: all 0.3s ease;
        }
        
        .dep-item:hover {
            border-color: #667eea;
            box-shadow: 0 4px 12px rgba(102, 126, 234, 0.2);
        }
        
        .dep-name {
            font-weight: 600;
            color: #333;
            margin-bottom: 8px;
            font-size: 0.95em;
        }
        
        .dep-status {
            display: inline-block;
            padding: 6px 12px;
            border-radius: 20px;
            font-size: 0.85em;
            font-weight: 600;
        }
        
        .dep-status.up {
            background: #E8F5E9;
            color: #2E7D32;
        }
        
        .dep-status.down {
            background: #FFEBEE;
            color: #C62828;
        }
        
        .status-dot {
            display: inline-block;
            width: 8px;
            height: 8px;
            border-radius: 50%;
            margin-right: 6px;
        }
        
        .status-dot.up {
            background: #4CAF50;
            animation: pulse-green 2s infinite;
        }
        
        .status-dot.down {
            background: #F44336;
        }
        
        @keyframes pulse-green {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.6; }
        }
        
        .timestamp {
            text-align: center;
            color: #999;
            font-size: 0.85em;
            padding-top: 20px;
            border-top: 1px solid #e0e0e0;
            margin-top: 30px;
        }
        
        .message {
            background: linear-gradient(135deg, rgba(76, 175, 80, 0.1), rgba(102, 126, 234, 0.1));
            border-left: 4px solid #4CAF50;
            padding: 16px;
            border-radius: 8px;
            margin-bottom: 30px;
            color: #333;
            font-weight: 500;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>⏱️ Simple Time Service</h1>
            <div class="status-badge healthy">
                <span class="status-dot up"></span>Running
            </div>
        </div>
        
        <div class="content">
            <div class="message">
                <strong>✓ {{ message }}</strong>
            </div>
            
            <div class="dependencies">
                <h3>📊 Dependencies Status</h3>
                <div class="dep-grid">
                    {% for dep, status in dependencies.items() %}
                    <div class="dep-item">
                        <div class="dep-name">{{ dep | replace('_', ' ') | title }}</div>
                        <div class="dep-status {{ status }}">
                            <span class="status-dot {{ status }}"></span>{{ status | upper }}
                        </div>
                    </div>
                    {% endfor %}
                </div>
            </div>
            
            <div class="info-grid">
                <div class="info-item">
                    <div class="info-label">Hostname</div>
                    <div class="info-value">{{ hostname }}</div>
                </div>
                
                <div class="info-item">
                    <div class="info-label">Operating System</div>
                    <div class="info-value">{{ os }}</div>
                </div>
                
                <div class="info-item">
                    <div class="info-label">Pod IP</div>
                    <div class="info-value">{{ pod_ip }}</div>
                </div>
                
                <div class="info-item">
                    <div class="info-label">Client IP</div>
                    <div class="info-value">{{ user_ip }}</div>
                </div>
                
                {% if proxy_chain != 'No proxy IPs found' %}
                <div class="info-item">
                    <div class="info-label">Proxy Chain</div>
                    <div class="info-value">{{ proxy_chain | join(' → ') }}</div>
                </div>
                {% endif %}
                
                <div class="info-item">
                    <div class="info-label">Timestamp (UTC)</div>
                    <div class="info-value">{{ timestamp }}</div>
                </div>
            </div>
            
            <div class="timestamp">
                Last updated: {{ timestamp }} • Status auto-refreshes every 30s
            </div>
        </div>
    </div>
    
    <script>
        // Auto-refresh every 30 seconds
        setTimeout(() => location.reload(), 30000);
    </script>
</body>
</html>
"""


def health_check():
    """Lightweight health check endpoint for Kubernetes probes"""
    if REQUEST_COUNT:
        REQUEST_COUNT.labels(method='GET', endpoint='/healthz', status='200').inc()
    return jsonify({"status": "healthy"}), 200

@app.route("/metrics", methods=["GET"])
def metrics():
    """Prometheus metrics endpoint"""
    if not REQUEST_COUNT:
        return jsonify({"error": "Prometheus not available"}), 503
    return generate_latest(), 200, {'Content-Type': CONTENT_TYPE_LATEST}

@app.route("/kafka/publish", methods=["POST"])
def kafka_publish():
    """Publish a custom event to Kafka"""
    if not kafka_producer:
        return jsonify({"error": "Kafka service not available"}), 503
    
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
    if not kafka_producer or not kafka_consumer:
        return jsonify({
            "status": "unavailable",
            "message": "Kafka services not initialized"
        }), 503
    
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
    if not kafka_producer:
        return jsonify({"status": "unavailable", "message": "Kafka producer not available"}), 503
    
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
    try:
        with ExitStack() as stack:
            # Handle request timing
            if REQUEST_DURATION:
                stack.enter_context(REQUEST_DURATION.labels(method='GET', endpoint='/').time())
            
            # Handle tracing
            if tracer:
                stack.enter_context(tracer.start_as_current_span("get_time_and_ip"))
            
            try:
                forwarded_for_list = request.headers.getlist("X-Forwarded-For")

                if forwarded_for_list:
                    all_ips = [ip.strip() for ip in forwarded_for_list[0].split(",") if ip.strip()]
                    user_ip = all_ips[0] if all_ips else request.remote_addr
                else:
                    all_ips = []
                    user_ip = request.remote_addr

                # Send request event to Kafka (if available)
                if kafka_producer:
                    try:
                        kafka_producer.send_request_event(
                            user_ip=user_ip,
                            method='GET',
                            endpoint='/',
                            hostname=hostname,
                            os=host_os
                        )
                    except Exception as e:
                        logger.warning(f"Failed to send Kafka request event: {str(e)}")

                # Build comprehensive status of all dependencies
                deps_status = {
                    "kafka": "up" if kafka_producer else "down",
                    "opentelemetry": "up" if tracer else "down",
                    "prometheus": "up" if (REQUEST_COUNT and REQUEST_DURATION) else "down",
                    "postgres": "up"
                }
                
                # Count running services
                running_services = sum(1 for status in deps_status.values() if status == "up")
                total_services = len(deps_status)
                
                response = {
                    "message": f"Time Service Running - {running_services}/{total_services} dependencies active",
                    "timestamp": datetime.utcnow().isoformat() + "Z",
                    "user_ip": user_ip,
                    "proxy_chain": all_ips if all_ips else "No proxy IPs found",
                    "hostname": hostname,
                    "os": host_os,
                    "pod_ip": pod_ip,
                    "dependencies": deps_status
                }
                
                # Set span attribute if tracing is enabled
                span = trace.get_current_span()
                if span and span.is_recording():
                    span.set_attribute("user_ip", user_ip)
                    span.set_attribute("has_proxy_chain", len(all_ips) > 0)
                
                logger.info(f"Request from {user_ip}", extra={"user_ip": user_ip, "proxy_chain": all_ips})
                
                # Send response event to Kafka (if available)
                if kafka_producer:
                    try:
                        kafka_producer.send_response_event(
                            user_ip=user_ip,
                            status_code=200,
                            response_time_ms=0
                        )
                    except Exception as e:
                        logger.warning(f"Failed to send Kafka response event: {str(e)}")
                
                if REQUEST_COUNT:
                    REQUEST_COUNT.labels(method='GET', endpoint='/', status='200').inc()
                
                # Return HTML or JSON based on Accept header
                if 'text/html' in request.headers.get('Accept', ''):
                    return render_template_string(STATUS_DASHBOARD, **response), 200, {'Content-Type': 'text/html'}
                else:
                    return jsonify(response), 200
            except Exception as e:
                logger.error(f"Error processing request: {str(e)}", exc_info=True)
                
                # Record exception in span if tracing is enabled
                span = trace.get_current_span()
                if span and span.is_recording():
                    span.record_exception(e)
                
                # Send error event to Kafka (if available)
                if kafka_producer:
                    try:
                        kafka_producer.send_error_event(
                            error_message=str(e),
                            error_type='request_processing_error',
                            endpoint='/'
                        )
                    except Exception as kafka_error:
                        logger.warning(f"Failed to send Kafka error event: {str(kafka_error)}")
                
                if REQUEST_COUNT:
                    REQUEST_COUNT.labels(method='GET', endpoint='/', status='500').inc()
                
                return jsonify({"error": "Internal server error"}), 500
    except Exception as e:
        logger.error(f"Unexpected error in request handler: {str(e)}", exc_info=True)
        return jsonify({"error": "Internal server error"}), 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)  # nosemgrep: python.flask.security.audit.app-run-param-config.avoid_app_run_with_bad_host
