# Single Cloud Run

The module deploys Cloud Run that communicates with Gemini APIs.

The deployment includes

- An exposure layer composed either by a Global external application load balancer (+ Cloud Armor IP allowlist security backend policy) or an internal application load balancer
- Cloud Run (accessible with custom service account, authentication, direct VPC egress)
- By default, a VPC, a subnet, private Google APIs routes and DNS policies
- By default, a project
