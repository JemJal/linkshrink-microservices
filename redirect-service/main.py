# redirect-service/main.py

import os
import json
import logging
from datetime import datetime, timezone
import ssl  # Import the standard SSL library

import pika  # Import pika for RabbitMQ
import redis # Import redis
import requests # Import requests for service-to-service calls
from fastapi import FastAPI, HTTPException, status
from starlette.responses import RedirectResponse

# ===================================================================
# ===               CONFIGURATION & CONNECTIONS                   ===
# ===================================================================

# Reading all connection details from environment variables
REDIS_HOST = os.getenv("REDIS_HOST", "localhost")
RABBITMQ_HOST = os.getenv("RABBITMQ_HOST", "localhost")
MQ_USERNAME = os.getenv("MQ_USERNAME", "guest")
MQ_PASSWORD = os.getenv("MQ_PASSWORD", "guest")
LINK_SERVICE_URL = os.getenv("LINK_SERVICE_URL", "http://link-service:8000")

# Standard setup for logging and the FastAPI application
logging.basicConfig(level=logging.INFO)
app = FastAPI(title="Redirect Service")

# Create a Redis client and check the connection on startup
try:
    redis_client = redis.Redis(host=REDIS_HOST, port=6379, db=0, decode_responses=True)
    redis_client.ping()
    logging.info(f"Successfully connected to Redis at {REDIS_HOST}")
except redis.exceptions.ConnectionError as e:
    logging.error(f"Could not connect to Redis: {e}")
    redis_client = None # Set to None so the app can still start if Redis is down

# ===================================================================
# ===                    HELPER FUNCTIONS                         ===
# ===================================================================

def publish_click_event(short_code: str):
    """
    Publishes a message to RabbitMQ when a link is clicked.
    This is an asynchronous "fire and forget" operation.
    """
    try:
        credentials = pika.PlainCredentials(MQ_USERNAME, MQ_PASSWORD)

        # --- THIS IS THE CRITICAL FIX for AWS MQ ---
        # AWS MQ on port 5671 requires a secure SSL/TLS connection.
        # We create a default SSL context and pass it to pika.
        context = ssl.create_default_context()
        ssl_options = pika.SSLOptions(context)
        
        connection = pika.BlockingConnection(
            pika.ConnectionParameters(
                host=RABBITMQ_HOST, 
                port=5671, 
                credentials=credentials, 
                ssl_options=ssl_options # Pass the SSL options here
            )
        )
        # --- END OF FIX ---
        
        channel = connection.channel()
        # 'durable=True' ensures the queue survives a broker restart
        channel.queue_declare(queue='clicks', durable=True)

        message = {
            "short_code": short_code,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }

        channel.basic_publish(
            exchange='',
            routing_key='clicks',
            body=json.dumps(message),
            # 'delivery_mode=2' makes the message itself persistent
            properties=pika.BasicProperties(delivery_mode=2)
        )
        logging.info(f"Successfully published click event for {short_code}")
        connection.close()
    except Exception as e:
        logging.error(f"Could not publish click event to RabbitMQ: {e}")

def get_link_from_api(short_code: str) -> str | None:
    """
    This function is called on a cache miss. It makes a direct, internal API call
    to the link-service to get the original URL for a given short code.
    """
    api_url = f"{LINK_SERVICE_URL}/internal/links/{short_code}"
    logging.info(f"Querying internal API: {api_url}")
    try:
        response = requests.get(api_url, timeout=2.0)
        
        if response.status_code == 200:
            data = response.json()
            return data.get("original_url")
        else:
            logging.warning(f"Link-service returned non-200 status: {response.status_code}")
            return None
    except requests.exceptions.RequestException as e:
        logging.error(f"Could not connect to link-service API: {e}")
        return None

# ===================================================================
# ===                     API ENDPOINTS                           ===
# ===================================================================

@app.get("/health", status_code=status.HTTP_200_OK)
def health_check():
    """Simple health check for the Application Load Balancer."""
    return {"status": "ok", "redis_connected": redis_client is not None}

@app.get("/{short_code}")
def perform_redirect(short_code: str):
    """
    This is the core endpoint. It handles a redirect request by first
    checking the Redis cache, and if not found, querying the link-service API.
    """
    logging.info(f"Redirect request received for short_code: {short_code}")

    original_url = None
    if redis_client:
        try:
            original_url = redis_client.get(short_code)
        except redis.exceptions.ConnectionError as e:
            logging.error(f"Redis connection error on get: {e}")
            # If Redis fails, we can still proceed to the API lookup
            original_url = None

    if original_url:
        logging.info(f"Cache hit for {short_code}. Redirecting.")
        publish_click_event(short_code)
        return RedirectResponse(url=original_url, status_code=status.HTTP_307_TEMPORARY_REDIRECT)
    else:
        logging.warning(f"Cache miss for {short_code}. Querying link-service API.")
        original_url = get_link_from_api(short_code)

        if original_url:
            logging.info(f"API hit for {short_code}. Caching result and redirecting.")
            if redis_client:
                try:
                    # Cache the result for 1 hour to speed up future requests.
                    redis_client.set(short_code, original_url, ex=3600)
                except redis.exceptions.ConnectionError as e:
                    logging.error(f"Redis connection error on set: {e}")
            
            publish_click_event(short_code)
            return RedirectResponse(url=original_url, status_code=status.HTTP_307_TEMPORARY_REDIRECT)
        else:
            logging.error(f"Short code '{short_code}' not found in cache or API.")
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Link not found")