#!/bin/bash
set -e # This makes the script exit immediately if any command fails

# --- 1. SET UP ENVIRONMENT ---
echo "--- Setting up AWS Environment Variables ---"
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
export AWS_REGION=$(aws configure get region)
export LATEST_TAG=$(git rev-parse --short HEAD)

# Verify they are set correctly
if [ -z "$AWS_ACCOUNT_ID" ] || [ -z "$AWS_REGION" ]; then
    echo "Error: AWS_ACCOUNT_ID or AWS_REGION is not set. Please configure your AWS CLI."
    exit 1
fi
echo "Account ID: $AWS_ACCOUNT_ID"
echo "Region: $AWS_REGION"
echo "Image Tag: $LATEST_TAG"
echo "-------------------------------------------"
echo ""

# --- 2. LOG IN TO ECR ---
echo "--- Logging into Amazon ECR ---"
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
echo "Login Succeeded."
echo "----------------------------------"
echo ""

# --- 3. BUILD AND PUSH SERVICES ---
# The service names must match the directory names exactly
SERVICES=("user-service" "link-service" "redirect-service" "analytics-service" "web-gui")

for SERVICE in "${SERVICES[@]}"
do
  echo "--- Building and Pushing $SERVICE ---"
  
  # The last argument ("$SERVICE") tells Docker to use that directory as the build context.
  docker build -t "$SERVICE:$LATEST_TAG" -f "$SERVICE/Dockerfile" "$SERVICE"
  
  # Tag and Push
  docker tag "$SERVICE:$LATEST_TAG" "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$SERVICE:$LATEST_TAG"
  docker push "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$SERVICE:$LATEST_TAG"
  
  echo "--- Done with $SERVICE ---"
  echo ""
done

echo "All images have been built and pushed successfully!"