# Fleet Ping Service

The Fleet Ping Service is a Node.js/Express backend service used to receive vehicle location updates and handle driver authentication.

The service uses PostgreSQL for persistent storage and is containerized using Docker.

## Technology Stack

* Node.js
* Express.js
* PostgreSQL
* Docker
* GitHub Actions

## API Endpoints

The service currently provides endpoints for:

* Driver login
* Vehicle location ping ingestion
* Fleet ping retrieval

Refer to the application source for endpoint definitions, request formats, and current behavior.

## Prerequisites

To run the service locally, ensure you have:

* Node.js
* npm
* PostgreSQL

Alternatively, the application and database can be started using Docker Compose.

## Local Setup

Install dependencies:

```bash
npm install
```

Configure the required environment variables using the provided environment configuration.

Start the application:

```bash
node server.js
```

The service will start on the configured application port.

## Database

The service uses PostgreSQL.

The initial database structure is available in:

```text
schema.sql
```

Apply the schema to your local PostgreSQL instance before running the application.

## Docker

The repository includes:

```text
Dockerfile
docker-compose.yml
```

To start the application using Docker Compose:

```bash
docker compose up --build
```

## Configuration

Application configuration is managed through environment variables.

Review the existing configuration and application source to determine the variables required to run the service.

## CI/CD

A GitHub Actions workflow is included in the repository.

Changes pushed to the `main` branch currently trigger the configured deployment workflow.

## Repository Structure

```text
.
├── .github/
│   └── workflows/
├── Dockerfile
├── docker-compose.yml
├── schema.sql
├── server.js
├── package.json
└── README.md
```

## Assessment Context

This repository is provided as part of the **VexarDrive Technologies DevOps & Cloud Infrastructure Engineer Technical Assessment**.

Review the repository in its current state before making changes.

Your assessment brief contains the requirements, expected deliverables, and submission instructions.