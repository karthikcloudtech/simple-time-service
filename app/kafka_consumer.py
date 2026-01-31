"""Kafka Consumer for simple-time-service"""
import json
import logging
import threading
import time
from typing import Callable, Optional, List
from kafka import KafkaConsumer
from kafka.errors import KafkaError
from prometheus_client import Counter, Histogram
from kafka_config import KAFKA_CONSUMER_CONFIG, KAFKA_TOPIC_EVENTS, KAFKA_TOPIC_REQUESTS

logger = logging.getLogger(__name__)

# Metrics for consumer
KAFKA_MESSAGES_RECEIVED = Counter(
    'kafka_messages_received_total',
    'Total Kafka messages received',
    ['topic', 'event_type', 'status']
)

KAFKA_CONSUMER_LAG = Histogram(
    'kafka_consumer_lag_ms',
    'Kafka consumer lag in milliseconds',
    ['topic']
)

KAFKA_MESSAGE_PROCESS_TIME = Histogram(
    'kafka_message_process_time_seconds',
    'Time to process a Kafka message',
    ['topic', 'event_type']
)


class KafkaConsumerService:
    """Service for consuming messages from Kafka"""
    
    def __init__(self, topics: Optional[List[str]] = None):
        """
        Initialize the Kafka consumer
        
        Args:
            topics: List of topics to subscribe to
        """
        self.topics = topics or [KAFKA_TOPIC_EVENTS, KAFKA_TOPIC_REQUESTS]
        self.consumer = None
        self.is_running = False
        self.consumer_thread = None
        self.message_handlers = {}
        self._lock = threading.Lock()
        
        self._initialize_consumer()
    
    def _initialize_consumer(self) -> bool:
        """Initialize the Kafka consumer"""
        try:
            self.consumer = KafkaConsumer(
                *self.topics,
                **KAFKA_CONSUMER_CONFIG,
                value_deserializer=lambda m: json.loads(m.decode('utf-8'))
            )
            logger.info(f"Kafka Consumer initialized successfully. Topics: {self.topics}")
            return True
        except Exception as e:
            logger.error(f"Failed to initialize Kafka Consumer: {str(e)}", exc_info=True)
            self.consumer = None
            return False
    
    def register_handler(
        self,
        event_type: str,
        handler: Callable[[dict], None]
    ) -> None:
        """
        Register a handler for a specific event type
        
        Args:
            event_type: Type of event to handle
            handler: Callable that processes the event
        """
        with self._lock:
            self.message_handlers[event_type] = handler
            logger.info(f"Registered handler for event type: {event_type}")
    
    def unregister_handler(self, event_type: str) -> None:
        """Unregister a handler"""
        with self._lock:
            if event_type in self.message_handlers:
                del self.message_handlers[event_type]
                logger.info(f"Unregistered handler for event type: {event_type}")
    
    def start(self) -> None:
        """Start consuming messages in a background thread"""
        if self.is_running:
            logger.warning("Consumer is already running")
            return
        
        if not self.consumer:
            logger.error("Consumer not initialized")
            return
        
        self.is_running = True
        self.consumer_thread = threading.Thread(target=self._consume_loop, daemon=True)
        self.consumer_thread.start()
        logger.info("Kafka Consumer started")
    
    def stop(self) -> None:
        """Stop consuming messages"""
        self.is_running = False
        if self.consumer_thread:
            self.consumer_thread.join(timeout=10)
        self._close_consumer()
        logger.info("Kafka Consumer stopped")
    
    def _consume_loop(self) -> None:
        """Main consume loop"""
        while self.is_running:
            try:
                for message in self.consumer:
                    if not self.is_running:
                        break
                    
                    try:
                        self._process_message(message)
                    except Exception as e:
                        logger.error(f"Error processing message: {str(e)}", exc_info=True)
                        KAFKA_MESSAGES_RECEIVED.labels(
                            topic=message.topic,
                            event_type='unknown',
                            status='error'
                        ).inc()
                        
            except KafkaError as e:
                logger.error(f"Kafka consumer error: {str(e)}", exc_info=True)
                if self.is_running:
                    time.sleep(5)  # Backoff before reconnecting
            except Exception as e:
                logger.error(f"Unexpected error in consume loop: {str(e)}", exc_info=True)
                if self.is_running:
                    time.sleep(5)
    
    def _process_message(self, message) -> None:
        """Process a single message"""
        start_time = time.time()
        
        try:
            value = message.value
            topic = message.topic
            
            # Extract event type
            event_type = value.get('event_type', 'unknown')
            
            # Calculate lag
            if message.timestamp:
                lag_ms = (time.time() * 1000) - (message.timestamp / 1000)
                KAFKA_CONSUMER_LAG.labels(topic=topic).observe(lag_ms)
            
            # Get handler for this event type
            with self._lock:
                handler = self.message_handlers.get(event_type)
            
            if handler:
                handler(value)
                status = 'success'
            else:
                logger.debug(f"No handler registered for event type: {event_type}")
                status = 'no_handler'
            
            # Track metrics
            process_time = time.time() - start_time
            KAFKA_MESSAGE_PROCESS_TIME.labels(topic=topic, event_type=event_type).observe(process_time)
            KAFKA_MESSAGES_RECEIVED.labels(
                topic=topic,
                event_type=event_type,
                status=status
            ).inc()
            
            logger.debug(
                f"Processed message - Topic: {topic}, Event: {event_type}, "
                f"Offset: {message.offset}, Time: {process_time:.3f}s"
            )
            
        except Exception as e:
            logger.error(f"Error processing message value: {str(e)}", exc_info=True)
            raise
    
    def _close_consumer(self) -> None:
        """Close the consumer connection"""
        if self.consumer:
            try:
                self.consumer.close(timeout_ms=10000)
                self.consumer = None
                logger.info("Kafka Consumer closed")
            except Exception as e:
                logger.error(f"Error closing Kafka Consumer: {str(e)}", exc_info=True)


# Global consumer instance (for singleton pattern with optional use)
_consumer_instance = None
_consumer_lock = threading.Lock()


def get_consumer(topics: Optional[List[str]] = None) -> KafkaConsumerService:
    """Get or create the Kafka consumer instance"""
    global _consumer_instance
    
    with _consumer_lock:
        if _consumer_instance is None:
            _consumer_instance = KafkaConsumerService(topics=topics)
        return _consumer_instance
