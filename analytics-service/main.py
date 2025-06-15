# analytics-service/main.py
import os
import pika
import time
import json

# --- Configuration & Connection ---
RABBITMQ_HOST = os.getenv("RABBITMQ_HOST", "localhost")

def main():
    # Loop to retry connection to RabbitMQ
    while True:
        try:
            connection = pika.BlockingConnection(pika.ConnectionParameters(host=RABBITMQ_HOST))
            channel = connection.channel()
            channel.queue_declare(queue='clicks')
            break # Exit loop if connection is successful
        except pika.exceptions.AMQPConnectionError:
            print("Connection to RabbitMQ failed. Retrying in 5 seconds...")
            time.sleep(5)

    # Define the callback function that will process messages
    def callback(ch, method, properties, body):
        message = json.loads(body)
        print(f" [x] Received click event for short_code: {message['short_code']}")
        # In a real application, you would write this to a database
        # e.g., db.execute("INSERT INTO clicks ...")
        ch.basic_ack(delivery_tag = method.delivery_tag)

    # Start consuming messages from the queue
    channel.basic_consume(queue='clicks', on_message_callback=callback)

    print(' [*] Waiting for messages. To exit press CTRL+C')
    channel.start_consuming()

if __name__ == '__main__':
    main()