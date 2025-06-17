# LinkShrink: A Complete Microservices-Powered URL Shortener

LinkShrink is a fully-featured URL shortening application built on a modern microservices architecture. It provides user authentication, authenticated link creation and management, high-performance redirects, and asynchronous click analytics. The entire system is designed for automated deployment to AWS using Terraform and GitHub Actions.

This repository serves as a complete, production-ready blueprint for deploying a complex, multi-service application to the cloud.

## Table of Contents

1.  [Project Overview](#project-overview)
2.  [System Architecture](#system-architecture)
3.  [File & Directory Structure](#file--directory-structure)
4.  [Getting Started: Local Development](#getting-started-local-development)
5.  [Cloud Deployment: The Automated CI/CD Pipeline](#cloud-deployment-the-automated-cicd-pipeline)
    -   [Step 1: Prerequisites](#step-1-prerequisites)
    -   [Step 2: GitHub Repository Secrets Setup](#step-2-github-repository-secrets-setup)
    -   [Step 3: The Automated Deployment](#step-3-the-automated-deployment)
6.  [Destroying the Cloud Infrastructure](#destroying-the-cloud-infrastructure)
7.  [Key Design Decisions & Concepts](#key-design-decisions--concepts)
8.  [Future Improvements](#future-improvements)

## Project Overview

This project demonstrates a real-world software development lifecycle, from local containerized development to a fully automated cloud deployment.

**Core Features:**

-   **User-Facing GUI:** A simple web interface for user registration, login, and link management.
-   **Authenticated API:** Users must be logged in to create or view their links.
-   **High-Performance Redirects:** A dedicated redirect service using a Redis cache for sub-millisecond lookups.
-   **Asynchronous Analytics:** Link clicks are processed in the background via a message queue (RabbitMQ) without slowing down the user redirect.
-   **Infrastructure as Code (IaC):** The entire AWS infrastructure is defined and managed by Terraform.
-   **Automated CI/CD:** A multi-stage GitHub Actions workflow automatically builds, tests (implicitly), and deploys the entire application on every push to the `main` branch.

## System Architecture

The system is composed of five distinct microservices and a suite of managed AWS services, all orchestrated by an Application Load Balancer.

```mermaid
graph TD
    subgraph "User's Browser"
        A["Web GUI"]
    end

    subgraph "AWS Cloud"
        subgraph "Application Load Balancer"
            B("Listener Rules")
        end

        subgraph "ECS Services on Fargate"
            C["Web GUI Service"]
            D["User Service"]
            E["Link Service"]
            F["Redirect Service"]
            G["Analytics Service"]
        end

        subgraph "Data Stores"
            H["User DB - Postgres"]
            I["Link DB - Postgres"]
            J["Redirect Cache - Redis"]
            K["Message Queue - RabbitMQ"]
        end
    end

    A -- "Requests" --> B

    B -- "API: /users or /token" --> D
    B -- "API: /links" --> E
    B -- "Redirects: /r/:shortcode" --> F
    B -- "Default Route for GUI" --> C

    D -- "Reads/Writes" --> H
    E -- "Reads/Writes" --> I
    E -- "Writes to Cache" --> J
    F -- "Cache Miss" --> E
    F -- "Cache Hit" --> J
    F -- "Publishes Click Event" --> K
    G -- "Consumes Events" --> K
```

## File & Directory Structure

This is a breakdown of all important files and directories in the project.

-   `.github/workflows/deploy.yml`: The brain of the CI/CD pipeline, defining the 3-phase automated deployment to AWS.
-   `analytics-service/`: Manages the background processing of link-click events.
    -   `Dockerfile`: Instructions to containerize the analytics service.
    -   `main.py`: The Python script that connects to RabbitMQ and consumes messages.
    -   `requirements.txt`: Python dependencies for this service.
-   `gateway/nginx.conf`: Nginx configuration used for the **local development** `docker-compose` setup.
-   `link-service/`: Handles the creation, retrieval, and storage of shortened links.
    -   `(files similar to analytics-service)`
-   `redirect-service/`: Provides high-performance redirects for short links using a Redis cache.
    -   `(files similar to analytics-service)`
-   `terraform/`: Contains all Infrastructure as Code (IaC) definitions.
    -   `backend.tf`: Configures the S3 backend for storing Terraform's state securely.
    -   `database.tf`: Defines the two RDS PostgreSQL database instances.
    -   `dependencies.tf`: Defines dependencies like Redis and RabbitMQ.
    -   `ecr.tf`: Defines the five ECR container registries for our Docker images.
    -   `ecs.tf`: Defines all ECS services-tasks, and the Application Load Balancer rules.
    -   `network.tf`: Defines the VPC, subnets, and routing for our cloud network.
    -   `outputs.tf`: Specifies what information to output after deployment (e.g., the website URL).
    -   `provider.tf`: Configures the AWS provider for Terraform.
    -   `security.tf`: Defines all security groups (firewall rules).
    -   `variables.tf`: Defines input variables for our Terraform configuration (like passwords).
    -   `vpc_endpoints.tf`: Creates VPC endpoints for secure, private communication with AWS services.
-   `user-service/`: Manages user registration, login, and authentication (JWT generation).
    -   `(files similar to analytics-service)`
-   `web-gui/`: The static frontend application.
    -   `Dockerfile`: A simple Nginx container to serve the static files in production.
    -   `static/`: Contains all HTML, CSS, and JavaScript files for the user interface.
-   `.dockerignore`: Specifies files and directories to ignore when building Docker images, ensuring fast and clean builds.
-   `.gitignore`: Specifies files to be ignored by Git (like secrets and Terraform state files).
-   `build-and-push.sh`: A local helper script for manually building and pushing all Docker images.
-   `docker-compose.yml`: Defines the entire application stack for easy **local development**.
-   `README.md`: This file.

## Getting Started: Local Development

Running the entire application on your local machine is simple and is the recommended way to develop new features.

**Prerequisites:**
-   Docker & Docker Compose

**Steps:**
1.  Clone this repository.
2.  From the root directory of the project, run the following command:
    ```bash
    docker-compose up --build
    ```
3.  Wait for all services to start.
4.  Open your web browser and navigate to `http://localhost:8080`.

You can now use the full application locally. Any code changes will be reflected the next time you run the command.

## Cloud Deployment: The Automated CI/CD Pipeline

This project is configured for fully automated deployment to AWS. After a one-time setup of secrets, every `git push` to the `main` branch will trigger a safe, multi-stage deployment.

### Step 1: Prerequisites

1.  **AWS Account:** You need an AWS account.
2.  **AWS CLI:** Install and configure the AWS CLI on your local machine:
    ```bash
    aws configure
    ```
    This will ask for your Access Key ID and Secret Access Key.
3.  **Terraform:** Install Terraform.
4.  **S3 Backend:** You must manually create an S3 bucket and a DynamoDB table for the Terraform backend as defined in `terraform/backend.tf` before the first deployment. This is a one-time setup.

### Step 2: GitHub Repository Secrets Setup

The GitHub Actions workflow requires access to sensitive information. You must store these as encrypted secrets in your repository.

1.  Navigate to your repository on GitHub.
2.  Go to **Settings** > **Secrets and variables** > **Actions**.
3.  Click **New repository secret** for each of the following:

| Secret Name                   | Description                                       | Example Value                   |
| ----------------------------- | ------------------------------------------------- | ------------------------------- |
| `AWS_ACCESS_KEY_ID`           | Your IAM user's Access Key ID.                    | `AKIAIOSFODNN7EXAMPLE`          |
| `AWS_SECRET_ACCESS_KEY`       | Your IAM user's Secret Access Key.                | `wJalrXUtnFEMI...`              |
| `TF_VAR_DB_PASSWORD`          | A strong password for the `user-db` database.     | `my-strong-password-123`        |
| `TF_VAR_LINK_DB_PASSWORD`     | A strong password for the `link-db` database.     | `another-secure-password-456`   |
| `TF_VAR_JWT_SECRET_KEY`       | A long, random string for signing JWTs.           | `5f4dcc3b5aa765d61d8...`      |
| `TF_VAR_MQ_PASSWORD`          | A strong password for the RabbitMQ user.          | `a-very-secure-mq-password`     |

*Note: The `TF_VAR_` prefix is important, as it allows Terraform to automatically recognize these as input variables.*

### Step 3: The Automated Deployment

With the secrets configured, the deployment process is now fully automated.

**How it works:**
1.  **Make a code change** (e.g., update a feature, fix a bug).
2.  **Commit and push** that change to the `main` branch:
    ```bash
    git commit -m "feat: Add new dashboard feature"
    git push origin main
    ```

**That's it!** Pushing to `main` automatically triggers the `.github/workflows/deploy.yml` workflow, which you can monitor in the "Actions" tab of your repository. It will execute three jobs in sequence:
1.  **Create ECR Repos:** Ensures the container registries exist.
2.  **Build and Push Images:** Builds fresh Docker images for all five services, tagging them with the unique Git commit hash.
3.  **Deploy ECS Services:** Runs `terraform apply` to create or update all the services, databases, and networking to run the new version of the code.

When the workflow is complete, the new version of your application will be live at the URL provided in the Terraform output.

## Destroying the Cloud Infrastructure

To avoid ongoing AWS costs, you can easily tear down the entire infrastructure with a single command.

1.  Navigate to the `/terraform` directory.
2.  Run the destroy command:
    ```bash
    terraform destroy
    ```
3.  Type `yes` to confirm. This will delete all resources created by Terraform.

## Key Design Decisions & Concepts

-   **Three-Phase Deployment:** The CI/CD pipeline is explicitly split into three jobs (Create Repos, Build Images, Deploy Services) to correctly handle infrastructure dependencies. You cannot push an image to a repository that doesn't exist.
-   **Immutable Image Tags:** ECR repositories are configured to be immutable. A specific tag (like a Git commit hash) can never be overwritten, ensuring deployment integrity and preventing accidental changes.
-   **Git Commit as Source of Truth:** The short Git commit hash is used as the Docker image tag. This creates a direct, auditable link between a specific version of the code in Git and the exact container running in production.

## Future Improvements

-   **Add HTTPS:** Implement an ACM certificate and update the ALB listener to use HTTPS on port 443 for secure traffic.
-   **Custom Domain:** Add Route 53 configuration to point a custom domain name to the Application Load Balancer.
-   **Unit & Integration Tests:** Add a testing stage to the CI/CD pipeline to automatically run tests before the deployment jobs.
-   **Staging Environment:** Duplicate the Terraform setup to create a separate "staging" environment for testing new features before deploying to production.