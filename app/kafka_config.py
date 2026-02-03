"""Kafka configuration"""
import os
import logging

logger = logging.getLogger(__name__)

# Kafka configuration from environment variables
KAFKA_BROKERS = os.getenv('KAFKA_BROKERS', 'localhost:9092').split(',')
KAFKA_TOPIC_EVENTS = os.getenv('KAFKA_TOPIC_EVENTS', 'simple-time-service-events')
KAFKA_CONSUMER_GROUP = os.getenv('KAFKA_CONSUMER_GROUP', 'simple-time-service-group')


def log_kafka_config():
    """Log Kafka configuration"""
    logger.info(f"Kafka Brokers: {KAFKA_BROKERS}")
    logger.info(f"Events Topic: {KAFKA_TOPIC_EVENTS}")
    logger.info(f"Consumer Group: {KAFKA_CONSUMER_GROUP}")
