# RAG with Cloud Run

The module deploys a "Retrieval-Augmented Generation" (RAG) system, leveraging Cloud Run, Vertex AI, Cloud SQL and BigQuery.

A Cloud Run job periodically ingests sample [movies data](./data/top-100-imdb-movies.csv) from BigQuery, creates embeddings and stores them in a Cloud SQL database (with pgvector). Another Cloud Run frontend application leverages the text embeddings from the Cloud SQL database and answers questions on these movies in json format.

<p align="center">
  <img src="diagram.png" alt="Components diagram">
</p>

The deployment includes

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
