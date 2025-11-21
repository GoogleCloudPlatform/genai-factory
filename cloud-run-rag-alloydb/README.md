# RAG with Cloud Run and AlloyDB

This module deploys a "Retrieval-Augmented Generation" (RAG) system, leveraging Cloud Run, AlloyDB and BigQuery. For the same architecture using Cloud SQL instead of AlloyDB, consult the [corresponding folder](../cloud-run-rag/README.md).

![Architecture Diagram](./diagram.png)

A Cloud Run job periodically ingests sample [movies data](./1-apps/data/top-100-imdb-movies.csv) from BigQuery, creates embeddings and stores them in an AlloyDB database. Another Cloud Run frontend application leverages the text embeddings from the AlloyDB database and answers questions on these movies in json format.

## Core Components

The deployment includes:

- An **ingestion subsystem**, made of a private **Cloud Run job** with direct egress access to the user VPC, that reads sample data from **BigQuery**, leverages the **Vertex Text Embeddings APIs** and stores results in **AlloyDB**
	
- **Databases**:
	- A **BigQuery dataset**, where users store their data to augment the model
	- A private **AlloyDB** instance where the ingestion job stores the text embeddings.
	  By default, this is PostgreSQL-compatible.

- A **frontend subsystem**, made of:
	- **Global external application load balancer** (+ Cloud Armor IP allowlist security backend policy + HTTP to HTTPS redirect + managed certificates). This is created by default.
	- **Internal application load balancer** (+ Cloud Armor IP allowlist security backend policy + HTTP to HTTPS redirect + managed certificates + CAS + Cloud DNS private zone). This is not created by default.
	- A private **Cloud Run** frontend with direct egress access to the user VPC, that answers user queries in json format, based on the text embeddings contained in the AlloyDB database.

- By default, a **VPC**, a subnet, private Google APIs routes and DNS policies. Optionally, can use your existing VPCs.
- By default, a **project** with all the necessary permissions. Optionally, can use your existing project.

## Apply the factory

- Enter the [0-projects](0-projects/README.md) folder and follow the instructions to setup your GCP project, service accounts and permissions
- Go to the [1-apps](1-apps/README.md) folder and follow the instructions to deploy the components inside the project
