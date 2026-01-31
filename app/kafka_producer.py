"""Kafka Producer for simple-time-service"""
import json
import logging
from datetime import datetime
from typing import Optional, Callable
from kafka import KafkaProducer
from kafka.errors import KafkaError
from prometheus_client import Counter, Histogram
from kafka_config import KAFKA_PRODUCER_CONFIG, KAFKA_TOPIC_EVENTS, KAFKA_TOPIC_REQUESTS

logger = logging.getLogger(__name__)

# Metrics for producer
KAFKA_MESSAGES_SENT = Counter(
    'kafka_messages_sent_total',
    'Total Kafka messages sent',
    ['topic', 'status']
)

KAFKA_MESSAGE_SIZE = Histogram(
    'kafka_message_size_bytes',
    'Kafka message size in bytes',
    ['topic']
)


class KafkaProducerService:
    """Service for producing messages to Kafka"""
    
    _instance = None
    
    def __new__(cls):
        if cls._instance is None:
            cls._instance = super(KafkaProducerService, cls).__new__(cls)
            cls._instance._initialized = False
        return cls._instance
    
    def __init__(self):
        if self._initialized:
            return
        
        try:
            self.producer = KafkaProducer(
                **KAFKA_PRODUCER_CONFIG,
                value_serializer=lambda v: json.dumps(v).encode('utf-8'),
                key_serializer=lambda k: k.encode('utf-8') if k else None
            )
            self._initialized = True
            logger.info("Kafka Producer initialized successfully")
        except Exception as e:
            logger.error(f"Failed to initialize Kafka Producer: {str(e)}", exc_info=True)
            self.producer = None
    
    def send_event(
        self,
        event_type: str,
        data: dict,
        topic: Optional[str] = None,
        key: Optional[str] = None,
        callback: Optional[Callable] = None
    ) -> bool:
        """
        Send an event to Kafka
        
        Args:
            event_type: Type of event (e.g., 'request', 'response', 'error')
            data: Event data as dictionary
            topic: Kafka topic (defaults to events topic)
            key: Message key for partitioning
            callback: Optional callback function
            
        Returns:
            bool: True if message was sent, False otherwise
        """
        if not self.producer:
            logger.error("Kafka Producer not initialized")
            return False
        
        if topic is None:
            topic = KAFKA_TOPIC_EVENTS
        
        try:
            message = {
                'timestamp': datetime.utcnow().isoformat() + 'Z',
                'event_type': event_type,
                'data': data
            }
            
            future = self.producer.send(
                topic,
                value=message,
                key=key
            )
            
            # Track metrics
            message_size = len(json.dumps(message).encode('utf-8'))
            KAFKA_MESSAGE_SIZE.labels(topic=topic).observe(message_size)
            
            # Register callback
            if callback:
                future.add_callback(callback)
            else:
                future.add_errback(self._error_callback)
            
            # Optional: Wait for send to complete (for critical messages)
            # record_metadata = future.get(timeout=10)
            
            KAFKA_MESSAGES_SENT.labels(topic=topic, status='success').inc()
            logger.debug(f"Event sent to topic '{topic}': {event_type}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to send event to Kafka: {str(e)}", exc_info=True)
            KAFKA_MESSAGES_SENT.labels(topic=topic, status='error').inc()
            return False
    
    def send_request_event(self, user_ip: str, method: str, endpoint: str, **extra_data) -> bool:
        """Send a request event"""
        data = {
            'user_ip': user_ip,
            'method': method,
            'endpoint': endpoint,
            **extra_data
        }
        return self.send_event(
            event_type='http_request',
            data=data,
            topic=KAFKA_TOPIC_REQUESTS,
            key=user_ip  # Partition by user_ip for ordering per user
        )
    
    def send_response_event(self, user_ip: str, status_code: int, response_time_ms: float, **extra_data) -> bool:
        """Send a response event"""
        data = {
            'user_ip': user_ip,
            'status_code': status_code,
            'response_time_ms': response_time_ms,
            **extra_data
        }
        return self.send_event(
            event_type='http_response',
            data=data,
            key=user_ip
        )
    
    def send_error_event(self, error_message: str, error_type: str, **extra_data) -> bool:
        """Send an error event"""
        data = {
            'error_message': error_message,
            'error_type': error_type,
            **extra_data
        }
        return self.send_event(
            event_type='error',
            data=data
        )
    
    def flush(self, timeout_ms: int = 10000) -> None:
        """Flush any pending messages"""
        if self.producer:
            try:
                self.producer.flush(timeout=timeout_ms / 1000)
                logger.info("Kafka Producer flushed")
            except Exception as e:
                logger.error(f"Error flushing Kafka Producer: {str(e)}", exc_info=True)
    
    def close(self) -> None:
        """Close the producer connection"""
        if self.producer:
            try:
                self.producer.close(timeout_secs=10)
                logger.info("Kafka Producer closed")
            except Exception as e:
                logger.error(f"Error closing Kafka Producer: {str(e)}", exc_info=True)
    
    @staticmethod
    def _error_callback(exc):
        """Default error callback"""
        logger.error(f"Kafka send failed: {exc}")


# Singleton instance
def get_producer() -> KafkaProducerService:
    """Get the Kafka producer instance"""
    return KafkaProducerService()
