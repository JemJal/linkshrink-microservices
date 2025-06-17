# redirect-service/main.py

import os
import json
import logging
from datetime import datetime, timezone

import pika
import redis
import requests # We need this library for service-to-service calls
from fastapi import FastAPI, HTTPException, status
from starlette.responses import RedirectResponse

# ===================================================================
# ===               CONFIGURATION & CONNECTIONS                   ===
# ===================================================================

# Reading all connection details from environment variables
# Defaults are provided for easy local development with docker-compose
REDIS_HOST = os.getenv("REDIS_HOST", "localhost")
RABBITMQ_HOST = os.getenv("RABBITMQ_HOST", "localhost")
MQ_USERNAME = os.getenv("MQ_USERNAME", "guest")
MQ_PASSWORD = os.getenv("MQ_PASSWORD", "guest")

# This new variable will hold the private DNS name of our link-service.
# In AWS, this will be something like 'http://link-service.linkshrink-cluster.local:8000'
# which Terraform will provide.
LINK_SERVICE_URL = os.getenv("LINK_SERVICE_URL", "http://link-service:8000")

# Standard setup
logging.basicConfig(level=logging.INFO)
app = FastAPI(title="Redirect Service")

# Create a Redis client. Redis client libraries are robust and handle
# connection pooling, making it safe to define globally.
try:
    redis_client = redis.Redis(host=REDIS_HOST, port=6379, db=0, decode_responses=True)
    redis_client.ping() # Check the connection on startup
    logging.info(f"Successfully connected to Redis at {REDIS_HOST}")
except redis.exceptions.ConnectionError as e:
    logging.error(f"Could not connect to Redis: {e}")
    redis_client = None # Set to None if connection fails

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
        # For AWS MQ, we connect to the secure AMQPS port 5671.
        # In a real production system, you would also configure SSL/TLS options.
        connection = pika.BlockingConnection(
            pika.ConnectionParameters(host=RABBITMQ_HOST, port=5671, credentials=credentials)
        )
        channel = connection.channel()
        channel.queue_declare(queue='clicks', durable=True) # Durable queues survive broker restarts

        message = {
            "short_code": short_code,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }

        channel.basic_publish(
            exchange='',
            routing_key='clicks',
            body=json.dumps(message),
            properties=pika.BasicProperties(delivery_mode=2) # Make message persistent
        )
        logging.info(f"Successfully published click event for {short_code}")
        connection.close()
    except Exception as e:
        # If we can't publish the event, we log the error but do NOT fail the redirect.
        # The user's experience is our top priority.
        logging.error(f"Could not publish click event to RabbitMQ: {e}")

def get_link_from_api(short_code: str) -> str | None:
    """
    This function is called on a cache miss. It makes a direct, internal API call
    to the link-service to get the original URL for a given short code.
    """
    # The URL points to an internal-only endpoint that we will create on the link-service.
    api_url = f"{LINK_SERVICE_URL}/internal/links/{short_code}"
    try:
        # We add a timeout to prevent this service from hanging if the link-service is slow.
        response = requests.get(api_url, timeout=2.0)
        
        # If the link-service finds the code, it returns a 200 OK.
        if response.status_code == 200:
            data = response.json()
            return data.get("original_url")
        # If the link-service returns 404, it means the link truly doesn't exist.
        elif response.status_code == 404:
            return None
        # Handle other potential errors from the link-service.
        else:
            logging.error(f"Link-service returned unexpected status code: {response.status_code}")
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
        original_url = redis_client.get(short_code)

    if original_url:
        # --- CACHE HIT ---
        logging.info(f"Cache hit for {short_code}. Redirecting.")
        publish_click_event(short_code)
        return RedirectResponse(url=original_url, status_code=status.HTTP_307_TEMPORARY_REDIRECT)
    else:
        # --- CACHE MISS ---
        logging.warning(f"Cache miss for {short_code}. Querying link-service API.")
        original_url = get_link_from_api(short_code)

        if original_url:
            logging.info(f"API hit for {short_code}. Caching result and redirecting.")
            if redis_client:
                # Cache the result for 1 hour to speed up future requests.
                redis_client.set(short_code, original_url, ex=3600)
            
            publish_click_event(short_code)
            return RedirectResponse(url=original_url, status_code=status.HTTP_307_TEMPORARY_REDIRECT)
        else:
            # The link was not found in the cache OR the main database. It doesn't exist.
            logging.error(f"Short code '{short_code}' not found in cache or API.")
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Link not found")
        
        # Trigger pipeline