from fastapi import FastAPI

# Create an instance of the FastAPI class
app = FastAPI(title="LinkShrink API Template")

# Define a "route" using a decorator
# This tells FastAPI that the function below handles GET requests to the /ping URL
@app.get("/ping")
def ping():
    """
    A simple endpoint to check if the service is alive.
    """
    # FastAPI will automatically convert this dictionary to a JSON response
    return {"response": "pong"}
