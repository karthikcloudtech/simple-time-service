"""FastAPI application for Simple Time Service"""
import logging
import os
import socket
import platform
from datetime import datetime
from contextlib import asynccontextmanager
from typing import Optional, List, Any

from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import JSONResponse, Response
from fastapi.templating import Jinja2Templates
import uvicorn
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.requests import RequestsInstrumentor

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

# Global state
hostname = socket.gethostname()
host_os = platform.system()
pod_ip: Optional[str] = None
kafka_producer = None
kafka_consumer = None
tracer = None
REQUEST_COUNT = None
REQUEST_DURATION = None

def get_pod_ip() -> Optional[str]:
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
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.settimeout(0)
        try:
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

def init_opentelemetry() -> Optional[Any]:
    """Initialize OpenTelemetry with graceful degradation"""
    try:
        resource = Resource.create({"service.name": "simple-time-service"})
        trace.set_tracer_provider(TracerProvider(resource=resource))
        tracer = trace.get_tracer(__name__)
        
        # Configure OTLP exporter
        otlp_exporter = OTLPSpanExporter(
            endpoint=os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://otel-collector:4317"),
            insecure=True
        )
        span_processor = BatchSpanProcessor(otlp_exporter)
        trace.get_tracer_provider().add_span_processor(span_processor)
        logger.info("OpenTelemetry initialized successfully")
        return tracer
    except Exception as e:
        logger.warning(f"OpenTelemetry initialization failed: {str(e)}. Continuing without tracing.")
        return None


def init_prometheus() -> tuple:
    """Initialize Prometheus metrics with graceful degradation"""
    try:
        request_count = Counter(
            'http_requests_total',
            'Total HTTP requests',
            ['method', 'endpoint', 'status']
        )
        request_duration = Histogram(
            'http_request_duration_seconds',
            'HTTP request duration',
            ['method', 'endpoint']
        )
        logger.info("Prometheus metrics initialized")
        return request_count, request_duration
    except Exception as e:
        logger.warning(f"Prometheus metrics initialization failed: {str(e)}")
        return None, None


def init_kafka() -> tuple:
    """Initialize Kafka with graceful degradation"""
    try:
        log_kafka_config()
        producer = get_producer()
        consumer = get_consumer()
        
        # Start consumer in background
        if consumer:
            consumer.start()
        
        logger.info("Kafka initialized successfully")
        return producer, consumer
    except Exception as e:
        logger.warning(f"Kafka initialization failed: {str(e)}. Continuing without Kafka support.")
        return None, None


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Lifespan context manager for startup and shutdown events"""
    global kafka_producer, kafka_consumer, tracer, REQUEST_COUNT, REQUEST_DURATION, pod_ip
    
    # Startup
    logger.info("Starting Simple Time Service...")
    
    # Initialize pod IP
    pod_ip = get_pod_ip()
    logger.info(f"Pod IP: {pod_ip}")
    
    # Initialize database
    try:
        init_db()
        logger.info("Database initialized successfully")
    except Exception as e:
        logger.warning(f"Database init failed: {str(e)}")
    
    # Initialize OpenTelemetry
    tracer = init_opentelemetry()
    
    # Initialize Prometheus
    REQUEST_COUNT, REQUEST_DURATION = init_prometheus()
    
    # Initialize Kafka
    kafka_producer, kafka_consumer = init_kafka()
    
    yield
    
    # Shutdown
    logger.info("Shutting down Simple Time Service...")
    try:
        if kafka_consumer:
            kafka_consumer.stop()
        if kafka_producer:
            kafka_producer.flush()
            kafka_producer.close()
    except Exception as e:
        logger.error(f"Error during Kafka cleanup: {str(e)}")
    
    logger.info("Shutdown complete")

# HTML Status Dashboard is now in templates/dashboard.html

def get_client_ip(request: Request) -> str:
    """Extract client IP from request, handling proxies"""
    forwarded_for_list = request.headers.getlist("X-Forwarded-For")
    
    if forwarded_for_list:
        all_ips = [ip.strip() for ip in forwarded_for_list[0].split(",") if ip.strip()]
        return all_ips[0] if all_ips else request.client.host
    
    return request.client.host if request.client else "unknown"


def get_proxy_chain(request: Request) -> List[str]:
    """Extract proxy chain from request"""
    forwarded_for_list = request.headers.getlist("X-Forwarded-For")
    
    if forwarded_for_list:
        all_ips = [ip.strip() for ip in forwarded_for_list[0].split(",") if ip.strip()]
        return all_ips if all_ips else []
    
    return []


# Create FastAPI app
app = FastAPI(
    title="Simple Time Service",
    description="A time service with HTTP request tracking and Kafka integration",
    version="1.0.0",
    lifespan=lifespan
)

# Setup Jinja2 templates
templates = Jinja2Templates(directory="templates")

# Instrument FastAPI and Requests
try:
    FastAPIInstrumentor.instrument_app(app)
    RequestsInstrumentor().instrument()
    logger.info("FastAPI and Requests instrumented")
except Exception as e:
    logger.warning(f"Failed to instrument FastAPI/Requests: {str(e)}")


@app.get("/healthz", tags=["Health"])
async def health_check():
    """Lightweight health check endpoint for Kubernetes probes"""
    if REQUEST_COUNT:
        REQUEST_COUNT.labels(method='GET', endpoint='/healthz', status='200').inc()
    return {"status": "healthy"}


@app.get("/metrics", tags=["Monitoring"])
async def metrics():
    """Prometheus metrics endpoint"""
    if not REQUEST_COUNT:
        raise HTTPException(status_code=503, detail="Prometheus not available")
    
    if REQUEST_COUNT:
        REQUEST_COUNT.labels(method='GET', endpoint='/metrics', status='200').inc()
    
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.post("/kafka/publish", tags=["Kafka"])
async def kafka_publish(request: Request):
    """Publish a custom event to Kafka"""
    if not kafka_producer:
        raise HTTPException(status_code=503, detail="Kafka service not available")
    
    try:
        data = await request.json()
        
        event_type = data.get('event_type', 'custom_event')
        event_data = data.get('data', {})
        topic = data.get('topic', None)
        
        success = kafka_producer.send_event(
            event_type=event_type,
            data=event_data,
            topic=topic
        )
        
        if REQUEST_COUNT:
            status = '200' if success else '500'
            REQUEST_COUNT.labels(method='POST', endpoint='/kafka/publish', status=status).inc()
        
        if success:
            return {
                "status": "success",
                "message": f"Event '{event_type}' published to Kafka",
                "event": {"event_type": event_type, "data": event_data}
            }
        else:
            raise HTTPException(status_code=500, detail="Failed to publish event to Kafka")
            
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error publishing to Kafka: {str(e)}", exc_info=True)
        if REQUEST_COUNT:
            REQUEST_COUNT.labels(method='POST', endpoint='/kafka/publish', status='500').inc()
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/kafka/status", tags=["Kafka"])
async def kafka_status():
    """Get Kafka status and configuration"""
    if not kafka_producer or not kafka_consumer:
        if REQUEST_COUNT:
            REQUEST_COUNT.labels(method='GET', endpoint='/kafka/status', status='503').inc()
        raise HTTPException(status_code=503, detail="Kafka services not initialized")
    
    try:
        producer_status = "connected" if kafka_producer.producer else "disconnected"
        consumer_status = "running" if kafka_consumer.is_running else "stopped"
        
        if REQUEST_COUNT:
            REQUEST_COUNT.labels(method='GET', endpoint='/kafka/status', status='200').inc()
        
        return {
            "kafka_producer": producer_status,
            "kafka_consumer": consumer_status,
            "consumer_topics": kafka_consumer.topics,
            "consumer_handlers": list(kafka_consumer.message_handlers.keys())
        }
    except Exception as e:
        logger.error(f"Error getting Kafka status: {str(e)}", exc_info=True)
        if REQUEST_COUNT:
            REQUEST_COUNT.labels(method='GET', endpoint='/kafka/status', status='500').inc()
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/kafka/flush", tags=["Kafka"])
async def kafka_flush():
    """Flush pending messages in Kafka producer"""
    if not kafka_producer:
        raise HTTPException(status_code=503, detail="Kafka producer not available")
    
    try:
        kafka_producer.flush()
        if REQUEST_COUNT:
            REQUEST_COUNT.labels(method='POST', endpoint='/kafka/flush', status='200').inc()
        return {"status": "success", "message": "Kafka producer flushed"}
    except Exception as e:
        logger.error(f"Error flushing Kafka producer: {str(e)}", exc_info=True)
        if REQUEST_COUNT:
            REQUEST_COUNT.labels(method='POST', endpoint='/kafka/flush', status='500').inc()
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/", tags=["Time Service"])
async def get_time_and_ip(request: Request):
    """Main endpoint - returns current time and request information"""
    try:
        user_ip = get_client_ip(request)
        proxy_chain = get_proxy_chain(request)
        current_time = datetime.utcnow().isoformat() + "Z"
        
        # Get current span for tracing
        span = trace.get_current_span()
        
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
        
        # Build dependency status
        deps_status = {
            "kafka": "up" if kafka_producer else "down",
            "opentelemetry": "up" if tracer else "down",
            "prometheus": "up" if (REQUEST_COUNT and REQUEST_DURATION) else "down",
            "postgres": "up"
        }
        
        running_services = sum(1 for status in deps_status.values() if status == "up")
        total_services = len(deps_status)
        
        response_data = {
            "message": f"Time Service Running - {running_services}/{total_services} dependencies active",
            "timestamp": current_time,
            "user_ip": user_ip,
            "proxy_chain": proxy_chain if proxy_chain else "No proxy IPs found",
            "hostname": hostname,
            "os": host_os,
            "pod_ip": pod_ip,
            "dependencies": deps_status
        }
        
        # Set span attributes for tracing
        if span and span.is_recording():
            span.set_attribute("user_ip", user_ip)
            span.set_attribute("has_proxy_chain", len(proxy_chain) > 0)
        
        logger.info(f"Request from {user_ip}", extra={"user_ip": user_ip, "proxy_chain": proxy_chain})
        
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
        
        # Check if client wants HTML
        if 'text/html' in request.headers.get('accept', ''):
            # Render Jinja2 template with context data
            template_context = {
                "request": request,
                "message": response_data["message"],
                "dependencies": deps_status,
                "hostname": hostname,
                "os": host_os,
                "pod_ip": pod_ip or "Not detected",
                "user_ip": user_ip,
                "proxy_chain": proxy_chain,
                "timestamp": current_time
            }
            return templates.TemplateResponse("dashboard.html", template_context)
        else:
            return JSONResponse(content=response_data, status_code=200)
            
    except Exception as e:
        logger.error(f"Error processing request: {str(e)}", exc_info=True)
        
        # Record exception in span for tracing
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
        
        raise HTTPException(status_code=500, detail="Internal server error")

if __name__ == "__main__":
    uvicorn.run(
        "app:app",
        host="0.0.0.0",
        port=8080,
        reload=os.getenv("RELOAD", "false").lower() == "true"
    )
