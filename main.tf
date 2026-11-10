##
# (c) 2021-2026
#     Cloud Ops Works LLC - https://cloudops.works/
#     Find us on:
#       GitHub: https://github.com/cloudopsworks
#       WebSite: https://cloudops.works
#     Distributed Under Apache v2.0 License
#

# Only nonrotating keys are Terraform-owned. The rotation Lambda owns the full
# lifecycle of rotating OpenRouter keys, including initial creation.
data "openrouter_workspaces" "lookup" {
  count = length(local.workspaces_requiring_lookup) > 0 ? 1 : 0
}

resource "openrouter_api_key" "this" {
  for_each = local.non_rotating_api_keys

  name                  = local.api_key_names[each.key]
  workspace_id          = each.value.workspace_id
  limit                 = each.value.limit
  limit_reset           = each.value.limit_reset
  include_byok_in_limit = each.value.include_byok_in_limit
  disabled              = each.value.disabled
  expires_at            = each.value.expires_at
  creator_user_id       = each.value.creator_user_id
}
