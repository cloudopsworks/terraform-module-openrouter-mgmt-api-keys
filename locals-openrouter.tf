##
# (c) 2021-2026
#     Cloud Ops Works LLC - https://cloudops.works/
#     Find us on:
#       GitHub: https://github.com/cloudopsworks
#       WebSite: https://cloudops.works
#     Distributed Under Apache v2.0 License
#

locals {
  workspaces_requiring_lookup = {
    for workspace_key, workspace in try(var.settings.workspaces, {}) : workspace_key => workspace
    if try(workspace.workspace_id, null) == null && (
      try(workspace.workspace_name, null) != null || try(workspace.workspace_slug, null) != null
    )
  }

  provider_workspaces = try(data.openrouter_workspaces.lookup[0].items, [])

  workspace_ids = {
    for workspace_key, workspace in try(var.settings.workspaces, {}) : workspace_key => coalesce(
      try(workspace.workspace_id, null),
      try(one([
        for candidate in local.provider_workspaces : candidate.id
        if try(workspace.workspace_name, null) != null && candidate.name == try(workspace.workspace_name, "")
      ]), null),
      try(one([
        for candidate in local.provider_workspaces : candidate.id
        if try(workspace.workspace_slug, null) != null && candidate.slug == try(workspace.workspace_slug, "")
      ]), null),
      null
    )
  }

  # Flatten workspaces -> api_keys into a single map keyed by "<workspace_key>/<api_key_key>".
  api_keys = {
    for item in flatten([
      for workspace_key, workspace in try(var.settings.workspaces, {}) : [
        for api_key_key, api_key in try(workspace.api_keys, {}) : {
          workspace_key         = workspace_key
          key                   = "${workspace_key}/${api_key_key}"
          workspace_id          = local.workspace_ids[workspace_key]
          workspace_name        = try(workspace.workspace_name, null)
          workspace_slug        = try(workspace.workspace_slug, null)
          name_prefix           = try(api_key.name_prefix, null)
          name                  = try(api_key.name, null)
          limit                 = try(api_key.limit, null)
          limit_reset           = try(api_key.limit_reset, null)
          include_byok_in_limit = try(api_key.include_byok_in_limit, null)
          disabled              = try(api_key.disabled, null)
          expires_at            = try(api_key.expires_at, null)
          creator_user_id       = try(api_key.creator_user_id, null)
          secret                = try(api_key.secret, {})
        }
      ]
    ]) : item.key => item
  }

  api_key_names = {
    for k, v in local.api_keys : k => (
      v.name_prefix != null
      ? "${v.name_prefix}-${local.system_name}"
      : v.name
    )
  }

  secret_names = {
    for k, v in local.api_keys : k => (
      try(v.secret.name_prefix, null) != null ? "${v.secret.name_prefix}-${local.system_name}" :
      try(v.secret.name, null) != null ? v.secret.name :
      v.name_prefix != null ? "${v.name_prefix}-${local.system_name}" :
      v.name
    )
  }

  secret_paths = {
    for k, v in local.api_keys : k => (
      try(v.secret.path, null) != null ? v.secret.path : format("%s/%s", local.secret_store_path, v.workspace_key)
    )
  }

  secret_plain = {
    for k, v in local.api_keys : k => try(v.secret.plain, false)
  }

  secret_descriptions = {
    for k, v in local.api_keys : k => try(v.secret.description, null)
  }
}
