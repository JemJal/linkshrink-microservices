# 1. Use an official Python runtime as a parent image
# The -slim version is smaller and good for production
FROM python:3.9-slim

# 2. Set the working directory in the container
WORKDIR /app

# 3. Copy the dependency list first to leverage Docker layer caching
# If requirements.txt doesn't change, Docker won't re-install dependencies
COPY requirements.txt requirements.txt

# 4. Install the dependencies
RUN pip install --no-cache-dir -r requirements.txt

# 5. Copy the rest of the application source code
COPY . .

# 6. Expose the port the app will run on
EXPOSE 8000

# 7. Define the command to run the application
# This runs the Uvicorn server, which hosts our FastAPI app
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]