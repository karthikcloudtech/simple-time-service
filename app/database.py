"""Database module for storing events using PostgreSQL"""
import psycopg2
from psycopg2.pool import SimpleConnectionPool
import os
import logging
from datetime import datetime
import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger(__name__)

# Function to retrieve password from AWS Secrets Manager
def get_db_password_from_secrets():
    """Retrieve DB password from AWS Secrets Manager"""
    secret_name = os.getenv('AWS_SECRET_NAME', 'simple-time-service-rds-credentials')
    region = os.getenv('AWS_REGION', 'us-east-1')
    
    try:
        client = boto3.client('secretsmanager', region_name=region)
        response = client.get_secret_value(SecretId=secret_name)
        if 'SecretString' in response:
            return response['SecretString']
        else:
            logger.error(f"No SecretString found in {secret_name}")
            return None
    except ClientError as e:
        logger.warning(f"Could not retrieve password from Secrets Manager: {str(e)}. Using fallback.")
        return os.getenv('DB_PASSWORD', 'changeme123')
    except Exception as e:
        logger.warning(f"Unexpected error retrieving from Secrets Manager: {str(e)}")
        return os.getenv('DB_PASSWORD', 'changeme123')

# PostgreSQL connection configuration
DB_HOST = os.getenv('DB_HOST', 'simple-time-service-postgres.co18eum88817.us-east-1.rds.amazonaws.com')
DB_PORT = os.getenv('DB_PORT', '5432')
DB_NAME = os.getenv('DB_NAME', 'appdb')
DB_USER = os.getenv('DB_USER', 'appuser')
DB_PASSWORD = get_db_password_from_secrets()

# Connection pool for better performance
conn_pool = None


def get_connection():
    """Get a database connection from the pool"""
    global conn_pool
    try:
        if conn_pool is None:
            conn_pool = SimpleConnectionPool(
                1,  # Minimum connections
                5,  # Maximum connections
                host=DB_HOST,
                port=int(DB_PORT),
                database=DB_NAME,
                user=DB_USER,
                password=DB_PASSWORD
            )
        return conn_pool.getconn()
    except Exception as e:
        logger.error(f"Failed to get database connection: {str(e)}")
        return None


def return_connection(conn):
    """Return a connection to the pool"""
    global conn_pool
    if conn_pool and conn:
        conn_pool.putconn(conn)


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
        logger.info(f"Database initialized successfully at {DB_HOST}:{DB_PORT}/{DB_NAME}")
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
