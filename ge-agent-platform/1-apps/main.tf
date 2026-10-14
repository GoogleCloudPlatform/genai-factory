# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

locals {
  _agent_registry_uri_prefix = "//agentregistry.googleapis.com/projects/${var.project_id}/locations"

  # Applied to every resource Terraform creates that supports a deletion
  # policy. The API refuses a destroy unless the policy is DELETE, so that is
  # what the off state has to be for a destroy to work at all.
  deletion_policy = var.enable_deletion_protection ? "PREVENT" : "DELETE"

  # The spec type is implied by the presence of spec content: each
  # service type only supports NO_SPEC and the value below.
  _spec_types = {
    agent      = "A2A_AGENT_CARD"
    endpoint   = null
    mcp_server = "TOOL_SPEC"
  }

  # Access policy rules declared directly on services registered by this stage,
  # flattened with the target policy id (defaulting to var.name).
  _svc_access_policy_rules = flatten([
    for k, v in local.agent_registry_services : [
      for rk, rv in v.access_policy_rules : {
        policy_id = coalesce(rv.policy_id, var.name)
        rule_key  = "${k}-${rk}"
        rule = merge(
          local._svc_ids[k],
          {
            condition            = rv.condition
            condition_service    = rv.condition_service
            description          = rv.description
            effect               = rv.effect
            excluded_permissions = rv.excluded_permissions
            excluded_principals  = rv.excluded_principals
            location             = v.location
            permissions          = rv.permissions
            principals           = rv.principals
            registry             = false
          }
        )
      }
    ]
  ])

  _svc_rules_by_policy = {
    for pid in distinct([for r in local._svc_access_policy_rules : r.policy_id]) :
    pid => {
      for r in local._svc_access_policy_rules :
      r.rule_key => r.rule if r.policy_id == pid
    }
  }

  _access_policy_ids = distinct(concat(
    keys(var.access_policies),
    keys(local._svc_rules_by_policy)
  ))

  # The attribute naming the registry resource of a service depends on
  # its type, and scopes the rule down from the whole registry.
  # IAP identifies a service by the id Agent Registry generates for
  # it, not by its service id, so rules are keyed on the last
  # segment of 'registry_resource'. Reading it back from the resource
  # also orders the access policy after the registration.
  _svc_ids = {
    for k, v in var.agent_registry_services : k => {
      agent_id      = v.type == "agent" ? local._svc_registry_ids[k] : null
      endpoint_id   = v.type == "endpoint" ? local._svc_registry_ids[k] : null
      mcp_server_id = v.type == "mcp_server" ? local._svc_registry_ids[k] : null
    }
  }

  _svc_registry_ids = {
    for k, v in var.agent_registry_services : k => basename(
      google_agent_registry_service.agent_registry_services[k].registry_resource
    )
  }

  # Merge stage-level access_policies with service-level access_policy_rules,
  # resolving any '*_id' attribute naming a service registered in this stage
  # to its generated registry id while passing external ids through unchanged.
  access_policies = {
    for pid in local._access_policy_ids : pid => {
      annotations       = try(var.access_policies[pid].annotations, null)
      bind              = try(var.access_policies[pid].bind, true)
      binding_condition = try(var.access_policies[pid].binding_condition, null)
      binding_id        = try(var.access_policies[pid].binding_id, null)
      display_name      = try(var.access_policies[pid].display_name, null)
      policy_reuse      = try(var.access_policies[pid].policy_reuse, null)
      target_resource   = try(var.access_policies[pid].target_resource, "project")
      rules = merge(
        {
          for rk, rv in try(var.access_policies[pid].rules, {}) : rk => merge(rv, {
            agent_id = (
              rv.agent_id == null
              ? null
              : lookup(local._svc_registry_ids, rv.agent_id, rv.agent_id)
            )
            endpoint_id = (
              rv.endpoint_id == null
              ? null
              : lookup(local._svc_registry_ids, rv.endpoint_id, rv.endpoint_id)
            )
            mcp_server_id = (
              rv.mcp_server_id == null
              ? null
              : lookup(local._svc_registry_ids, rv.mcp_server_id, rv.mcp_server_id)
            )
          })
        },
        lookup(local._svc_rules_by_policy, pid, {})
      )
    }
  }

  agent_registry_uris = {
    eu       = "${local._agent_registry_uri_prefix}/eu"
    global   = "${local._agent_registry_uri_prefix}/global"
    regional = "${local._agent_registry_uri_prefix}/${var.region}"
    us       = "${local._agent_registry_uri_prefix}/us"
  }

  # Derive the spec type from the service type and the presence of
  # spec content, so that the spec blocks in the resource can be
  # driven by a uniform object. If content is a path to an existing
  # file, load it; otherwise treat it as an inline JSON string.
  agent_registry_services = {
    for k, v in var.agent_registry_services : k => merge(v, {
      content = v.content == null ? null : (
        fileexists("${path.module}/${v.content}")
        ? file("${path.module}/${v.content}")
        : (fileexists(v.content) ? file(v.content) : v.content)
      )
      location = coalesce(v.location, var.region)
      spec_type = (
        v.content == null
        ? "NO_SPEC"
        : local._spec_types[v.type]
      )
    })
  }

  subnetwork = lookup(
    var.subnet_self_links, var.networking_config.subnet, var.networking_config.subnet
  )
}
