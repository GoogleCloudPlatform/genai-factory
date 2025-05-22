module "cloud_run" {
  source           = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/cloud-run-v2"
  project_id       = var.project_config.project_id
  name             = var.name
  region           = var.region
  ingress          = var.cloud_run_configs.ingress
  containers       = var.cloud_run_configs.containers
  service_account  = var.service_accounts["project/gf-srun-0"].email
  managed_revision = false
  iam = {
    "roles/run.invoker" = var.cloud_run_configs.service_invokers
  }
  revision = {
    gen2_execution_environment = true
    max_instance_count         = var.cloud_run_configs.max_instance_count
    vpc_access = {
      egress  = var.cloud_run_configs.vpc_access_egress
      network = local.vpc_id
      subnet  = local.subnet_id
      tags    = var.cloud_run_configs.vpc_access_tags
    }
  }
  deletion_protection = var.enable_deletion_protection
}
