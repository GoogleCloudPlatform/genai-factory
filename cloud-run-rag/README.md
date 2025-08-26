# RAG with Cloud Run and Cloud SQL

The module deploys a "Retrieval-Augmented Generation" (RAG) system, leveraging Cloud Run, Cloud SQL and BigQuery.

![Architecture Diagram](./diagram.png)

A Cloud Run job periodically ingests sample [movies data](./1-apps/data/top-100-imdb-movies.csv) from BigQuery, creates embeddings and stores them in a Cloud SQL database (with pgvector). Another Cloud Run frontend application leverages the text embeddings from the Cloud SQL database and answers questions on these movies in json format.

## Core Components

The deployment includes:

- An **ingestion subsystem**, made of a private **Cloud Run job** with direct egress access to the user VPC, that reads sample data from **BigQuery**, leverages the **Vertex Text Embeddings APIs** and stores results in **Cloud SQL**
	
- **Databases**:
	- A **BigQuery dataset**, where users store their data to augment the model
	- A private **Cloud SQL** instance where the ingestion job stores the text embeddings.
	  By default, this is PostgreSQL with the pgvector extension enabled.

- A **frontend subsystem**, made of:
	- **Global external application load balancer** (+ Cloud Armor IP allowlist security backend policy + HTTP to HTTPS redirect + managed certificates). This is created by default.
	- **Internal application load balancer** (+ Cloud Armor IP allowlist security backend policy + HTTP to HTTPS redirect + managed certificates + CAS + Cloud DNS private zone). This is not created by default.
	- A private **Cloud Run** frontend with direct egress access to the user VPC, that answers user queries in json format, based on the text embeddings contained in the Cloud SQL database.

- By default, a **VPC**, a subnet, private Google APIs routes and DNS policies. Optionally, can use your existing VPCs.
- By default, a **project** with all the necessary permissions. Optionally, can use your existing project.

## Deployment

To deploy this solution, follow these steps:

1.  **Set up your environment:** Ensure you have the Google Cloud SDK installed and configured.
2.  **Project Setup:** Navigate to the `0-projects` directory and follow the instructions in the `README.md` to set up your GCP project, service accounts, and permissions.
3.  **Application Deployment:** Navigate to the `1-apps` directory and follow the instructions in the `README.md` to deploy the application components.

## API

The frontend Cloud Run service exposes the following endpoint:

*   `POST /`

    This endpoint accepts a JSON payload with a "question" field and returns a JSON response with the answer.

    **Example Request:**

    ```json
    {
        "question": "What are the best movies by Quentin Tarantino?"
    }
    ```

    **Example Response:**

    ```json
    {
        "answer": "Quentin Tarantino has directed several acclaimed movies, including Pulp Fiction and Once Upon a Time in Hollywood."
    }
    ```

## Customization

You can customize the application by modifying the following:

*   **Data:** Replace the sample movie data in BigQuery with your own dataset.
*   **Model:** The application uses the Vertex Text Embeddings API by default. You can switch to a different embedding model by modifying the code in the `1-apps` directory.
*   **Frontend:** The frontend is a simple Cloud Run application. You can customize it to meet your specific needs.
