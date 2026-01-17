project_config = {
  id     = "test-project"
  number = "123456789"
}
name = "test-agent"
region = "europe-west1"
service_accounts = {
  "project/agent" = {
    email     = "agent@test-project.iam.gserviceaccount.com"
    iam_email = "serviceAccount:agent@test-project.iam.gserviceaccount.com"
    id        = "projects/test-project/serviceAccounts/agent@test-project.iam.gserviceaccount.com"
  }
}
