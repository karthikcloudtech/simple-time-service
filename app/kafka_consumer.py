"""Simplified Kafka Consumer - writes events to database"""
import json
import logging
import threading
from kafka import KafkaConsumer
from kafka_config import KAFKA_BROKERS, KAFKA_TOPIC_EVENTS, KAFKA_CONSUMER_GROUP
from database import insert_request, insert_response, insert_error

logger = logging.getLogger(__name__)


class KafkaConsumerService:
    """Simple Kafka consumer service - persists events to DB"""
    
    def __init__(self, topics=None):
        self.topics = topics or [KAFKA_TOPIC_EVENTS]
        self.consumer = None
        self.is_running = False
        self.consumer_thread = None
        self.message_handlers = {}
        self._lock = threading.Lock()
        
        try:
            self.consumer = KafkaConsumer(
                *self.topics,
                bootstrap_servers=KAFKA_BROKERS,
                group_id=KAFKA_CONSUMER_GROUP,
                auto_offset_reset='earliest',
                enable_auto_commit=True,
                value_deserializer=lambda m: json.loads(m.decode('utf-8'))
            )
            logger.info(f"Kafka Consumer initialized. Topics: {self.topics}")
        except Exception as e:
            logger.warning(f"Kafka Consumer init failed: {str(e)}")
            self.consumer = None
    
    def register_handler(self, event_type: str, handler):
        """Register a handler for event type"""
        with self._lock:
            self.message_handlers[event_type] = handler
            logger.info(f"Registered handler: {event_type}")
    
    def start(self):
        """Start consuming in background thread"""
        if self.is_running or not self.consumer:
            return
        
        self.is_running = True
        self.consumer_thread = threading.Thread(target=self._consume_loop, daemon=True)
        self.consumer_thread.start()
        logger.info("Kafka Consumer started - events persisted to database")
    
    def stop(self):
        """Stop consumer"""
        self.is_running = False
        if self.consumer_thread:
            self.consumer_thread.join(timeout=5)
        if self.consumer:
            try:
                self.consumer.close()
            except Exception as e:
                logger.warning(f"Close error: {str(e)}")
        logger.info("Kafka Consumer stopped")
    
    def _consume_loop(self):
        """Main consume loop - persists events to database"""
        while self.is_running and self.consumer:
            try:
                for message in self.consumer:
                    if not self.is_running:
                        break
                    
                    try:
                        value = message.value
                        event_type = value.get('event_type', 'unknown')
                        data = value.get('data', {})
                        
                        # Persist to database based on event type
                        if event_type == 'http_request':
                            insert_request(
                                user_ip=data.get('user_ip'),
                                method=data.get('method'),
                                endpoint=data.get('endpoint'),
                                hostname=data.get('hostname'),
                                os=data.get('os')
                            )
                        elif event_type == 'http_response':
                            insert_response(
                                user_ip=data.get('user_ip'),
                                status_code=data.get('status_code'),
                                response_time_ms=data.get('response_time_ms', 0)
                            )
                        elif event_type == 'error':
                            insert_error(
                                error_message=data.get('error_message'),
                                error_type=data.get('error_type'),
                                endpoint=data.get('endpoint')
                            )
                        
                        logger.debug(f"Persisted: {event_type} to database")
                    except Exception as e:
                        logger.warning(f"Error processing message: {str(e)}")
                        
            except Exception as e:
                logger.warning(f"Consumer error: {str(e)}")
                if self.is_running:
                    import time
                    time.sleep(2)


def get_consumer(topics=None) -> KafkaConsumerService:
    """Get consumer instance"""
    return KafkaConsumerService(topics=topics)
