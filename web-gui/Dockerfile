# Use a very small, official Nginx image as our base
FROM nginx:1.21-alpine

# Remove the default Nginx welcome page
RUN rm /etc/nginx/conf.d/default.conf

# Copy our static files from the local machine into the container's web root directory
# The path is relative to the build context, which is the project root.
COPY ./web-gui/static /usr/share/nginx/html