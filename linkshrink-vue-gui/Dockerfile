# --- Stage 1: The Builder ---
# This stage installs dependencies and builds our static Vue files.
FROM node:lts-alpine as builder

WORKDIR /app

# Copy package files and install dependencies
COPY package*.json ./
RUN npm install

# Copy the rest of the source code
COPY . .

# Build the production-optimized static files
RUN npm run build

# The result of this stage is a '/app/dist' folder containing our built UI.

# --- Stage 2: The Final Nginx Server ---
# This stage creates the tiny final image that will be deployed.
FROM nginx:stable-alpine

# Copy the built static files from the 'builder' stage
COPY --from=builder /app/dist /usr/share/nginx/html

# Copy our custom Nginx configuration
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Expose port 80 and start Nginx
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]