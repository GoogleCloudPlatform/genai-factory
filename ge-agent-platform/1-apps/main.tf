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

  # Bindings declared on the services registered by this stage. They
  # are normalized to the shape the gateway module expects, so that
  # they can be merged with the stage-level ones.
  _svc_iam = merge([
    for k, v in local.agent_registry_services : {
      for role, members in v.iam : "${k}/${role}" => merge(
        local._svc_ids[k],
        {
          condition = null
          location  = v.location
          members   = members
          role      = role
        }
      )
    }
  ]...)

  _svc_iam_bindings = merge([
    for k, v in local.agent_registry_services : {
      for bk, bv in v.iam_bindings : "${k}/${bk}" => merge(
        local._svc_ids[k],
        {
          condition = bv.condition
          location  = v.location
          members   = bv.members
          role      = bv.role
        }
      )
    }
  ]...)

  _svc_iam_bindings_additive = merge([
    for k, v in local.agent_registry_services : {
      for bk, bv in v.iam_bindings_additive : "${k}/${bk}" => merge(
        local._svc_ids[k],
        {
          condition = bv.condition
          location  = v.location
          member    = bv.member
          role      = bv.role
        }
      )
    }
  ]...)

  # The attribute naming the registry resource of a service depends on
  # its type, and scopes the bindings down from the whole registry.
  # IAP identifies a service by the id Agent Registry generates for
  # it, not by its service id, so bindings are keyed on the last
  # segment of 'registry_resource'. Reading it back from the resource
  # also orders the bindings after the registration.
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

  # Stage-level bindings target the whole registry, unless one of the
  # '*_id' attributes narrows them down to a single resource. An id
  # naming a service registered here is resolved to its generated
  # registry id; anything else is passed through, so that resources
  # registered outside this stage can be targeted too.
  _top_iam_bindings = {
    for k, v in var.agent_registry_iam_bindings : k => {
      agent_id = (
        v.agent_id == null
        ? null
        : lookup(local._svc_registry_ids, v.agent_id, v.agent_id)
      )
      condition = v.condition
      endpoint_id = (
        v.endpoint_id == null
        ? null
        : lookup(local._svc_registry_ids, v.endpoint_id, v.endpoint_id)
      )
      location = v.location
      mcp_server_id = (
        v.mcp_server_id == null
        ? null
        : lookup(local._svc_registry_ids, v.mcp_server_id, v.mcp_server_id)
      )
      members = v.members
      role    = v.role
    }
  }

  _top_iam_bindings_additive = {
    for k, v in var.agent_registry_iam_bindings_additive : k => {
      agent_id = (
        v.agent_id == null
        ? null
        : lookup(local._svc_registry_ids, v.agent_id, v.agent_id)
      )
      condition = v.condition
      endpoint_id = (
        v.endpoint_id == null
        ? null
        : lookup(local._svc_registry_ids, v.endpoint_id, v.endpoint_id)
      )
      location = v.location
      mcp_server_id = (
        v.mcp_server_id == null
        ? null
        : lookup(local._svc_registry_ids, v.mcp_server_id, v.mcp_server_id)
      )
      member = v.member
      role   = v.role
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

  registry_iam_bindings = merge(
    local._svc_iam, local._svc_iam_bindings, local._top_iam_bindings
  )

  registry_iam_bindings_additive = merge(
    local._svc_iam_bindings_additive, local._top_iam_bindings_additive
  )

  subnetwork = lookup(
    var.subnet_self_links, var.networking_config.subnet, var.networking_config.subnet
  )
}
