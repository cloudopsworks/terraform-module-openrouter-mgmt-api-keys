##
# (c) 2021-2026
#     Cloud Ops Works LLC - https://cloudops.works/
#     Find us on:
#       GitHub: https://github.com/cloudopsworks
#       WebSite: https://cloudops.works
#     Distributed Under Apache v2.0 License
#

# Creates an OpenRouter API key for each configured entry across all configured workspaces.
# The resource key is "<workspace_key>/<api_key_key>" and the generated secret is persisted
# immediately to AWS Secrets Manager because the actual API key is only returned on create.
data "openrouter_workspaces" "lookup" {
  count = length(local.workspaces_requiring_lookup) > 0 ? 1 : 0
}

resource "openrouter_api_key" "this" {
  for_each = local.api_keys

  name                  = local.api_key_names[each.key]
  workspace_id          = each.value.workspace_id
  limit                 = each.value.limit
  limit_reset           = each.value.limit_reset
  include_byok_in_limit = each.value.include_byok_in_limit
  disabled              = each.value.disabled
  expires_at            = each.value.expires_at
  creator_user_id       = each.value.creator_user_id

  lifecycle {
    precondition {
      condition = (
        (each.value.workspace_name == null && each.value.workspace_slug == null) ||
        each.value.workspace_id != null
      )
      error_message = "Each settings.workspaces.<workspace> entry that sets workspace_name or workspace_slug must resolve to exactly one existing OpenRouter workspace."
    }
  }
}
