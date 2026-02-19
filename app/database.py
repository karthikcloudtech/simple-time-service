"""Database module for storing events using PostgreSQL"""
import psycopg2
from psycopg2.pool import SimpleConnectionPool
import os
import logging
import json
from datetime import datetime
import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger(__name__)

# PostgreSQL connection via Secrets Manager
def connect_to_postgres_with_secrets(secret_name, region_name='us-east-1'):
    """
    Connect to PostgreSQL using credentials from Secrets Manager
    """
    # Get credentials from Secrets Manager
    client = boto3.client('secretsmanager', region_name=region_name)
    
    try:
        response = client.get_secret_value(SecretId=secret_name)
        secret = json.loads(response['SecretString'])
        
        # Get database name (hardcoded to 'simple')
        database = 'simple_time_service'
        connection = psycopg2.connect(
            db_host = 'simple-time-service-postgres.co18eum88817.us-east-1.rds.amazonaws.com',
            port=secret.get('port', 5432),
            database=database,
            user=secret['username'],
            password=secret['password']
        )
        
        logger.info(f"Connected to PostgreSQL at {secret['host']}:{secret.get('port', 5432)}/{database} as {secret['username']}")
        return connection
        
    except Exception as e:
        logger.error(f"Error connecting to database: {str(e)}")
        return None


# Secrets Manager configuration
SECRET_NAME = os.getenv('AWS_SECRET_NAME', 'rds!db-d3383bf3-468c-4942-86f3-89af40e59872')
REGION_NAME = os.getenv('AWS_REGION', 'us-east-1')


def get_connection():
    """Get a database connection using Secrets Manager"""
    try:
        conn = connect_to_postgres_with_secrets(SECRET_NAME, REGION_NAME)
        return conn
    except Exception as e:
        logger.error(f"Failed to get database connection: {str(e)}")
        return None


def return_connection(conn):
    """Close a database connection"""
    if conn:
        try:
            conn.close()
        except Exception as e:
            logger.warning(f"Error closing connection: {str(e)}")


def init_db():
    """Initialize database with tables"""
    try:
        conn = get_connection()
        if not conn:
            logger.error("Could not connect to database")
            return False

        cursor = conn.cursor()

        # Create requests table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS http_requests (
                id SERIAL PRIMARY KEY,
                timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                user_ip TEXT,
                method TEXT,
                endpoint TEXT,
                hostname TEXT,
                os TEXT
            )
        ''')

        # Create responses table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS http_responses (
                id SERIAL PRIMARY KEY,
                timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                user_ip TEXT,
                status_code INTEGER,
                response_time_ms FLOAT
            )
        ''')

        # Create errors table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS errors (
                id SERIAL PRIMARY KEY,
                timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                error_message TEXT,
                error_type TEXT,
                endpoint TEXT
            )
        ''')

        # Create indexes for better query performance
        cursor.execute('CREATE INDEX IF NOT EXISTS idx_http_requests_timestamp ON http_requests(timestamp)')
        cursor.execute('CREATE INDEX IF NOT EXISTS idx_http_responses_timestamp ON http_responses(timestamp)')
        cursor.execute('CREATE INDEX IF NOT EXISTS idx_errors_timestamp ON errors(timestamp)')

        conn.commit()
        logger.info("Database initialized successfully")
        return True
    except Exception as e:
        logger.warning(f"Database init failed: {str(e)}")
        return False
    finally:
        if conn:
            return_connection(conn)


def insert_request(user_ip: str, method: str, endpoint: str, hostname: str, os: str):
    """Insert HTTP request event"""
    try:
        conn = get_connection()
        if not conn:
            logger.error("Could not connect to database")
            return False
        
        cursor = conn.cursor()
        cursor.execute('''
            INSERT INTO http_requests (timestamp, user_ip, method, endpoint, hostname, os)
            VALUES (CURRENT_TIMESTAMP, %s, %s, %s, %s, %s)
        ''', (user_ip, method, endpoint, hostname, os))
        conn.commit()
        return True
    except Exception as e:
        logger.warning(f"Failed to insert request: {str(e)}")
        return False
    finally:
        if conn:
            return_connection(conn)


def insert_response(user_ip: str, status_code: int, response_time_ms: float):
    """Insert HTTP response event"""
    try:
        conn = get_connection()
        if not conn:
            logger.error("Could not connect to database")
            return False
        
        cursor = conn.cursor()
        cursor.execute('''
            INSERT INTO http_responses (timestamp, user_ip, status_code, response_time_ms)
            VALUES (CURRENT_TIMESTAMP, %s, %s, %s)
        ''', (user_ip, status_code, response_time_ms))
        conn.commit()
        return True
    except Exception as e:
        logger.warning(f"Failed to insert response: {str(e)}")
        return False
    finally:
        if conn:
            return_connection(conn)


def insert_error(error_message: str, error_type: str, endpoint: str = None):
    """Insert error event"""
    try:
        conn = get_connection()
        if not conn:
            logger.error("Could not connect to database")
            return False
        
        cursor = conn.cursor()
        cursor.execute('''
            INSERT INTO errors (timestamp, error_message, error_type, endpoint)
            VALUES (CURRENT_TIMESTAMP, %s, %s, %s)
        ''', (error_message, error_type, endpoint))
        conn.commit()
        return True
    except Exception as e:
        logger.warning(f"Failed to insert error: {str(e)}")
        return False
    finally:
        if conn:
            return_connection(conn)
