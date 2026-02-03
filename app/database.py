"""Database module for storing events"""
import sqlite3
import os
import logging
from datetime import datetime

logger = logging.getLogger(__name__)

DB_PATH = os.getenv('DB_PATH', '/tmp/events.db')


def init_db():
    """Initialize database with tables"""
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        
        # Create requests table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS http_requests (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp DATETIME,
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
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp DATETIME,
                user_ip TEXT,
                status_code INTEGER,
                response_time_ms FLOAT
            )
        ''')
        
        # Create errors table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS errors (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp DATETIME,
                error_message TEXT,
                error_type TEXT,
                endpoint TEXT
            )
        ''')
        
        conn.commit()
        conn.close()
        logger.info(f"Database initialized at {DB_PATH}")
        return True
    except Exception as e:
        logger.warning(f"Database init failed: {str(e)}")
        return False


def insert_request(user_ip: str, method: str, endpoint: str, hostname: str, os: str):
    """Insert HTTP request event"""
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute('''
            INSERT INTO http_requests (timestamp, user_ip, method, endpoint, hostname, os)
            VALUES (?, ?, ?, ?, ?, ?)
        ''', (datetime.utcnow().isoformat(), user_ip, method, endpoint, hostname, os))
        conn.commit()
        conn.close()
        return True
    except Exception as e:
        logger.warning(f"Failed to insert request: {str(e)}")
        return False


def insert_response(user_ip: str, status_code: int, response_time_ms: float):
    """Insert HTTP response event"""
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute('''
            INSERT INTO http_responses (timestamp, user_ip, status_code, response_time_ms)
            VALUES (?, ?, ?, ?)
        ''', (datetime.utcnow().isoformat(), user_ip, status_code, response_time_ms))
        conn.commit()
        conn.close()
        return True
    except Exception as e:
        logger.warning(f"Failed to insert response: {str(e)}")
        return False


def insert_error(error_message: str, error_type: str, endpoint: str = None):
    """Insert error event"""
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute('''
            INSERT INTO errors (timestamp, error_message, error_type, endpoint)
            VALUES (?, ?, ?, ?)
        ''', (datetime.utcnow().isoformat(), error_message, error_type, endpoint))
        conn.commit()
        conn.close()
        return True
    except Exception as e:
        logger.warning(f"Failed to insert error: {str(e)}")
        return False
