"""Simplified Kafka Producer"""
import json
import logging
from datetime import datetime
from kafka import KafkaProducer
from kafka_config import KAFKA_BROKERS, KAFKA_TOPIC_EVENTS

logger = logging.getLogger(__name__)


class KafkaProducerService:
    """Simple Kafka producer service"""
    
    def __init__(self):
        self.producer = None
        try:
            self.producer = KafkaProducer(
                bootstrap_servers=KAFKA_BROKERS,
                value_serializer=lambda v: json.dumps(v).encode('utf-8')
            )
            logger.info("Kafka Producer initialized")
        except Exception as e:
            logger.warning(f"Kafka Producer init failed: {str(e)}")
            self.producer = None
    
    def send_event(self, event_type: str, data: dict, topic: str = None) -> bool:
        """Send an event to Kafka"""
        if not self.producer:
            return False
        
        try:
            topic = topic or KAFKA_TOPIC_EVENTS
            message = {
                'timestamp': datetime.utcnow().isoformat() + 'Z',
                'event_type': event_type,
                'data': data
            }
            self.producer.send(topic, value=message)
            return True
        except Exception as e:
            logger.warning(f"Failed to send event: {str(e)}")
            return False
    
    def send_request_event(self, user_ip: str, method: str, endpoint: str, **extra) -> bool:
        """Send a request event"""
        return self.send_event('http_request', {
            'user_ip': user_ip,
            'method': method,
            'endpoint': endpoint,
            **extra
        })
    
    def send_response_event(self, user_ip: str, status_code: int, response_time_ms: float, **extra) -> bool:
        """Send a response event"""
        return self.send_event('http_response', {
            'user_ip': user_ip,
            'status_code': status_code,
            'response_time_ms': response_time_ms,
            **extra
        })
    
    def send_error_event(self, error_message: str, error_type: str, **extra) -> bool:
        """Send an error event"""
        return self.send_event('error', {
            'error_message': error_message,
            'error_type': error_type,
            **extra
        })
    
    def flush(self) -> None:
        """Flush pending messages"""
        if self.producer:
            try:
                self.producer.flush(timeout=10)
            except Exception as e:
                logger.warning(f"Flush error: {str(e)}")
    
    def close(self) -> None:
        """Close the producer"""
        if self.producer:
            try:
                self.producer.close()
            except Exception as e:
                logger.warning(f"Close error: {str(e)}")


def get_producer() -> KafkaProducerService:
    """Get producer instance"""
    return KafkaProducerService()
