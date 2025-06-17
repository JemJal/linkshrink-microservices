# Use a very small, official Nginx image as our base
FROM nginx:1.21-alpine

# Remove the default Nginx welcome page configuration
RUN rm /etc/nginx/conf.d/default.conf

# Copy our custom, simple Nginx configuration into the container
COPY ./nginx.conf /etc/nginx/conf.d/default.conf

# Copy our static files from the local machine into the container's web root directory
COPY ./static /usr/share/nginx/html