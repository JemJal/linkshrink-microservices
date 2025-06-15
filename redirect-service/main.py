# redirect-service/main.py

import os
import redis
import pika
import json
from fastapi import FastAPI, HTTPException
from starlette.responses import RedirectResponse
import logging

# --- Configuration ---
REDIS_HOST = os.getenv("REDIS_HOST", "localhost")
RABBITMQ_HOST = os.getenv("RABBITMQ_HOST", "localhost")
logging.basicConfig(level=logging.INFO)

# --- Connections ---
app = FastAPI(title="Redirect Service")
# We only connect to Redis globally because Redis clients handle connection pooling and are built for this.
redis_client = redis.Redis(host=REDIS_HOST, port=6379, db=0, decode_responses=True)

# --- Seeding some initial data for testing ---
redis_client.set("gogl", "https://www.google.com")
redis_client.set("ghub", "https://www.github.com")
logging.info("Seeded initial data into Redis: gogl, ghub")

# This is the new, more robust way of publishing a message
def publish_click_event(short_code: str):
    try:
        connection = pika.BlockingConnection(pika.ConnectionParameters(host=RABBITMQ_HOST))
        channel = connection.channel()
        channel.queue_declare(queue='clicks')
        
        message = {
            "short_code": short_code,
            "timestamp": "some-iso-timestamp", # In real app, use datetime.utcnow().isoformat()
        }
        
        channel.basic_publish(exchange='',
                              routing_key='clicks',
                              body=json.dumps(message))
        
        logging.info(f"Successfully published click event for {short_code}")
        connection.close()
    except pika.exceptions.AMQPConnectionError as e:
        # Log the error but don't crash the redirect. This makes the system resilient.
        logging.error(f"Could not connect to RabbitMQ to publish click event: {e}")

@app.get("/{short_code}")
def perform_redirect(short_code: str):
    original_url = redis_client.get(short_code)
    
    if original_url is None:
        raise HTTPException(status_code=404, detail="Short code not found")
    
    # Asynchronously send a message using our new function
    publish_click_event(short_code)

    return RedirectResponse(url=original_url, status_code=302)