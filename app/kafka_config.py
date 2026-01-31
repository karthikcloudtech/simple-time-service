"""Kafka configuration and utilities"""
import os
import logging
from typing import List

logger = logging.getLogger(__name__)

# Kafka configuration from environment variables
KAFKA_BROKERS = os.getenv('KAFKA_BROKERS', 'localhost:9092').split(',')
KAFKA_TOPIC_EVENTS = os.getenv('KAFKA_TOPIC_EVENTS', 'simple-time-service-events')
KAFKA_TOPIC_REQUESTS = os.getenv('KAFKA_TOPIC_REQUESTS', 'simple-time-service-requests')
KAFKA_CONSUMER_GROUP = os.getenv('KAFKA_CONSUMER_GROUP', 'simple-time-service-group')
KAFKA_AUTO_OFFSET_RESET = os.getenv('KAFKA_AUTO_OFFSET_RESET', 'earliest')

# Kafka client configuration
KAFKA_CLIENT_CONFIG = {
    'bootstrap_servers': KAFKA_BROKERS,
    'request_timeout_ms': 30000,
    'session_timeout_ms': 30000,
    'connections_max_idle_ms': 540000,
}

KAFKA_PRODUCER_CONFIG = {
    **KAFKA_CLIENT_CONFIG,
    'acks': 'all',
    'retries': 3,
    'max_in_flight_requests_per_connection': 1,
    'compression_type': 'gzip',
}

KAFKA_CONSUMER_CONFIG = {
    **KAFKA_CLIENT_CONFIG,
    'group_id': KAFKA_CONSUMER_GROUP,
    'auto_offset_reset': KAFKA_AUTO_OFFSET_RESET,
    'enable_auto_commit': True,
    'auto_commit_interval_ms': 5000,
    'max_poll_records': 100,
    'session_timeout_ms': 30000,
}


def get_kafka_brokers() -> List[str]:
    """Get list of Kafka brokers"""
    return KAFKA_BROKERS


def get_kafka_config() -> dict:
    """Get Kafka configuration"""
    return {
        'brokers': KAFKA_BROKERS,
        'events_topic': KAFKA_TOPIC_EVENTS,
        'requests_topic': KAFKA_TOPIC_REQUESTS,
        'consumer_group': KAFKA_CONSUMER_GROUP,
    }


def log_kafka_config():
    """Log Kafka configuration (for debugging)"""
    logger.info(f"Kafka Brokers: {KAFKA_BROKERS}")
    logger.info(f"Events Topic: {KAFKA_TOPIC_EVENTS}")
    logger.info(f"Requests Topic: {KAFKA_TOPIC_REQUESTS}")
    logger.info(f"Consumer Group: {KAFKA_CONSUMER_GROUP}")
