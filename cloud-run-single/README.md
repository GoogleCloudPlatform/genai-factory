# Single Cloud Run

The module deploys a Cloud Run instance that communicates with Gemini APIs.

The deployment includes

- A Global external application load balancer (+ Cloud Armor IP allowlist security backend policy)
- Cloud Run (accessible with custom service account, authentication, direct VPC egress)
- By default, a VPC, a subnet, private Google APIs routes, and DNS policies
- By default, a project
