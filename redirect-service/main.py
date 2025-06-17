# redirect-service/main.py

import os
import json
import logging
from datetime import datetime, timezone
import ssl
from typing import Union # <-- IMPORT 'Union' FOR OLDER PYTHON COMPATIBILITY

import pika
import redis
import requests
from fastapi import FastAPI, HTTPException, status
from starlette.responses import RedirectResponse

# ===================================================================
# ===               CONFIGURATION & CONNECTIONS                   ===
# ===================================================================

REDIS_HOST = os.getenv("REDIS_HOST", "localhost")
RABBITMQ_HOST = os.getenv("RABBITMQ_HOST", "localhost")
MQ_USERNAME = os.getenv("MQ_USERNAME", "guest")
MQ_PASSWORD = os.getenv("MQ_PASSWORD", "guest")
LINK_SERVICE_URL = os.getenv("LINK_SERVICE_URL", "")

logging.basicConfig(level=logging.INFO)
app = FastAPI(title="Redirect Service")

try:
    redis_client = redis.Redis(host=REDIS_HOST, port=6379, db=0, decode_responses=True)
    redis_client.ping()
    logging.info(f"Successfully connected to Redis at {REDIS_HOST}")
except redis.exceptions.ConnectionError as e:
    logging.error(f"Could not connect to Redis: {e}")
    redis_client = None

# ===================================================================
# ===                    HELPER FUNCTIONS                         ===
# ===================================================================

def publish_click_event(short_code: str):
    """Publishes a message to RabbitMQ when a link is clicked."""
    try:
        credentials = pika.PlainCredentials(MQ_USERNAME, MQ_PASSWORD)
        context = ssl.create_default_context()
        ssl_options = pika.SSLOptions(context)
        
        connection = pika.BlockingConnection(
            pika.ConnectionParameters(
                host=RABBITMQ_HOST, 
                port=5671, 
                credentials=credentials, 
                ssl_options=ssl_options
            )
        )
        
        channel = connection.channel()
        channel.queue_declare(queue='clicks', durable=True)

        message = {
            "short_code": short_code,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }

        channel.basic_publish(
            exchange='',
            routing_key='clicks',
            body=json.dumps(message),
            properties=pika.BasicProperties(delivery_mode=2)
        )
        logging.info(f"Successfully published click event for {short_code}")
        connection.close()
    except Exception as e:
        logging.error(f"Could not publish click event to RabbitMQ: {e}")

# --- THIS IS THE CORRECTED FUNCTION SIGNATURE ---
def get_link_from_api(short_code: str) -> Union[str, None]:
# -----------------------------------------------
    """
    Called on a cache miss. Makes an internal API call to the link-service.
    """
    # NOTE: In the next topic, we will create this internal endpoint.
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
    Core redirect endpoint using the read-through cache pattern.
    """
    logging.info(f"Redirect request received for short_code: {short_code}")

    original_url = None
    if redis_client:
        try:
            original_url = redis_client.get(short_code)
        except redis.exceptions.ConnectionError as e:
            logging.error(f"Redis connection error on get: {e}")
            original_url = None

    if original_url:
        logging.info(f"Cache hit for {short_code}. Redirecting.")
        publish_click_event(short_code)
        # Use HTTP 307 to indicate a temporary redirect.
        return RedirectResponse(url=original_url, status_code=status.HTTP_307_TEMPORARY_REDIRECT)
    else:
        logging.warning(f"Cache miss for {short_code}. Querying link-service API.")
        original_url = get_link_from_api(short_code)

        if original_url:
            logging.info(f"API hit for {short_code}. Caching result and redirecting.")
            if redis_client:
                try:
                    redis_client.set(short_code, original_url, ex=3600) # Cache for 1 hour
                except redis.exceptions.ConnectionError as e:
                    logging.error(f"Redis connection error on set: {e}")
            
            publish_click_event(short_code)
            return RedirectResponse(url=original_url, status_code=status.HTTP_307_TEMPORARY_REDIRECT)
        else:
            logging.error(f"Short code '{short_code}' not found in cache or API.")
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Link not found")