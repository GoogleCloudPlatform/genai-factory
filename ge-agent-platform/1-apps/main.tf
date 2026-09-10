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

  # Registry-level authoritative bindings. Bindings by principal are
  # inverted and merged into the role-keyed ones, while the keyed
  # bindings stay separate as they support conditions.
  _iam_principal_roles = distinct(flatten(values(
    var.agent_registry_iam_by_principals
  )))

  _iam_principals = {
    for r in local._iam_principal_roles : r => [
      for k, v in var.agent_registry_iam_by_principals :
      k if try(index(v, r), null) != null
    ]
  }

  # Each registry resource type is governed by a different resource,
  # so bindings are grouped by the type of their target.
  _iam_types = ["agent", "endpoint", "mcp_server", "registry"]

  # The spec type is implied by the presence of spec content: each
  # service type only supports NO_SPEC and the value below.
  _spec_types = {
    agent      = "A2A_AGENT_CARD"
    endpoint   = null
    mcp_server = "TOOL_SPEC"
  }

  # Bindings declared on the services registered by this stage. The
  # target type is taken from the service definition itself.
  _svc_iam = flatten([
    for k, v in var.agent_registry_services : [
      for role, members in v.iam : {
        id      = k
        members = members
        role    = role
        type    = v.type
      }
    ]
  ])

  _svc_iam_bindings = merge([
    for k, v in var.agent_registry_services : {
      for bk, bv in v.iam_bindings : "${k}/${bk}" => {
        condition = bv.condition
        id        = k
        members   = bv.members
        role      = bv.role
        type      = v.type
      }
    }
  ]...)

  _svc_iam_bindings_additive = merge([
    for k, v in var.agent_registry_services : {
      for bk, bv in v.iam_bindings_additive : "${k}/${bk}" => {
        condition = bv.condition
        id        = k
        member    = bv.member
        role      = bv.role
        type      = v.type
      }
    }
  ]...)

  # Top-level bindings target the whole registry, unless one of the
  # '*_id' attributes narrows them down to a single resource. This
  # also allows targeting resources registered outside this stage.
  _top_iam_bindings = {
    for k, v in var.agent_registry_iam_bindings : k => {
      condition = v.condition
      id = coalesce(
        v.agent_id, v.endpoint_id, v.mcp_server_id, "registry"
      )
      members = v.members
      role    = v.role
      type = (
        v.agent_id != null
        ? "agent"
        : (
          v.endpoint_id != null
          ? "endpoint"
          : (v.mcp_server_id != null ? "mcp_server" : "registry")
        )
      )
    }
  }

  _top_iam_bindings_additive = {
    for k, v in var.agent_registry_iam_bindings_additive : k => {
      condition = v.condition
      id = coalesce(
        v.agent_id, v.endpoint_id, v.mcp_server_id, "registry"
      )
      member = v.member
      role   = v.role
      type = (
        v.agent_id != null
        ? "agent"
        : (
          v.endpoint_id != null
          ? "endpoint"
          : (v.mcp_server_id != null ? "mcp_server" : "registry")
        )
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
  # driven by a uniform object.
  agent_registry_services = {
    for k, v in var.agent_registry_services : k => merge(v, {
      spec_type = (
        v.content == null
        ? "NO_SPEC"
        : local._spec_types[v.type]
      )
    })
  }

  iam = {
    for role in distinct(concat(
      keys(var.agent_registry_iam), keys(local._iam_principals)
    )) :
    role => concat(
      try(var.agent_registry_iam[role], []),
      try(local._iam_principals[role], [])
    )
  }

  service_iam = {
    for t in local._iam_types : t => {
      for b in local._svc_iam :
      "${b.id}/${b.role}" => b if b.type == t
    }
  }

  service_iam_bindings = {
    for t in local._iam_types : t => {
      for k, v in merge(
        local._svc_iam_bindings, local._top_iam_bindings
      ) : k => v if v.type == t
    }
  }

  service_iam_bindings_additive = {
    for t in local._iam_types : t => {
      for k, v in merge(
        local._svc_iam_bindings_additive,
        local._top_iam_bindings_additive
      ) : k => v if v.type == t
    }
  }

  subnetwork = lookup(
    var.subnet_self_links, var.networking_config.subnet, var.networking_config.subnet
  )
}
