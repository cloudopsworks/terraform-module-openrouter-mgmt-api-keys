##
# (c) 2021-2026
#     Cloud Ops Works LLC - https://cloudops.works/
#     Find us on:
#       GitHub: https://github.com/cloudopsworks
#       WebSite: https://cloudops.works
#     Distributed Under Apache v2.0 License
#

# settings:                               # (Optional) Settings for OpenRouter workspace API key management
#   workspaces:                           # (Optional) Map of OpenRouter workspaces keyed by a logical name
#     engineering:                        # Logical key used to identify the workspace in this module
#       workspace_id: "ws_1234567890"    # (Required) OpenRouter workspace UUID
#       api_keys:                         # (Optional) Map of API key configurations keyed by logical name
#         backend-service:
#           name_prefix: "backend"       # (Optional) Name prefix; final name = name_prefix + "-" + system_name
#           name: "fixed-name"           # (Optional) Fixed name for the API key (mutually exclusive with name_prefix)
#           limit: 250                    # (Optional) Spending limit in USD
#           limit_reset: "monthly"       # (Optional) Reset interval. Valid values: daily, weekly, monthly
#           include_byok_in_limit: true   # (Optional) Whether BYOK usage counts toward the limit
#           disabled: false               # (Optional) Whether the key is disabled. Default: provider default
#           expires_at: "2026-12-31T23:59:59Z" # (Optional) UTC ISO-8601 expiration timestamp
#           creator_user_id: "user_123"  # (Optional) OpenRouter organization member ID to set as creator
#           secret:                       # (Optional) AWS Secrets Manager configuration for storing the API key
#             name_prefix: "backend"     # (Optional) Secret name prefix; final name = name_prefix + "-" + system_name
#             name: "fixed-secret"       # (Optional) Fixed secret name (mutually exclusive with secret.name_prefix)
#             path: "/custom/path"       # (Optional) Secret path prefix. Default: /<org_unit>/<env_name>/<env_type>/<workspace_key>
#             plain: false                # (Optional) Store API key as plain string; default false stores JSON {"api_key":"<value>"}
#             description: "..."         # (Optional) Human-readable description for the Secrets Manager secret
variable "settings" {
  description = "Settings for OpenRouter workspace API key management and AWS Secrets Manager persistence"
  type = object({
    workspaces = optional(map(object({
      workspace_id = string
      api_keys = optional(map(object({
        name_prefix           = optional(string)
        name                  = optional(string)
        limit                 = optional(number)
        limit_reset           = optional(string)
        include_byok_in_limit = optional(bool)
        disabled              = optional(bool)
        expires_at            = optional(string)
        creator_user_id       = optional(string)
        secret = optional(object({
          name_prefix = optional(string)
          name        = optional(string)
          path        = optional(string)
          plain       = optional(bool, false)
          description = optional(string)
        }), {})
      })), {})
    })), {})
  })
  default = {}

  validation {
    condition = alltrue(flatten([
      for workspace in values(try(var.settings.workspaces, {})) : [
        for api_key in values(try(workspace.api_keys, {})) : (
          try(api_key.name_prefix, null) != null || try(api_key.name, null) != null
        )
      ]
    ]))
    error_message = "Each settings.workspaces.<workspace>.api_keys.<key> entry must define either name_prefix or name."
  }

  validation {
    condition = alltrue(flatten([
      for workspace in values(try(var.settings.workspaces, {})) : [
        for api_key in values(try(workspace.api_keys, {})) : !(
          try(api_key.name_prefix, null) != null && try(api_key.name, null) != null
        )
      ]
    ]))
    error_message = "Each settings.workspaces.<workspace>.api_keys.<key> entry must set only one of name_prefix or name."
  }

  validation {
    condition = alltrue(flatten([
      for workspace in values(try(var.settings.workspaces, {})) : [
        for api_key in values(try(workspace.api_keys, {})) : (
          try(api_key.limit_reset, null) == null || contains(["daily", "weekly", "monthly"], api_key.limit_reset)
        )
      ]
    ]))
    error_message = "Each settings.workspaces.<workspace>.api_keys.<key>.limit_reset must be one of daily, weekly, monthly, or null."
  }

  validation {
    condition = alltrue(flatten([
      for workspace in values(try(var.settings.workspaces, {})) : [
        for api_key in values(try(workspace.api_keys, {})) : try(api_key.limit, null) == null || try(api_key.limit, 0) >= 0
      ]
    ]))
    error_message = "Each settings.workspaces.<workspace>.api_keys.<key>.limit must be greater than or equal to zero."
  }

  validation {
    condition = alltrue(flatten([
      for workspace in values(try(var.settings.workspaces, {})) : [
        for api_key in values(try(workspace.api_keys, {})) : (
          try(api_key.expires_at, null) == null || can(formatdate("", api_key.expires_at))
        )
      ]
    ]))
    error_message = "Each settings.workspaces.<workspace>.api_keys.<key>.expires_at must be a valid UTC RFC3339 / ISO-8601 timestamp."
  }

  validation {
    condition = alltrue(flatten([
      for workspace in values(try(var.settings.workspaces, {})) : [
        for api_key in values(try(workspace.api_keys, {})) : !(
          try(api_key.secret.name_prefix, null) != null && try(api_key.secret.name, null) != null
        )
      ]
    ]))
    error_message = "Each settings.workspaces.<workspace>.api_keys.<key>.secret entry must set only one of secret.name_prefix or secret.name."
  }
}
