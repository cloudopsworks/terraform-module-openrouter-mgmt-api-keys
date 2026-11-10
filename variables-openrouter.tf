##
# (c) 2021-2026
#     Cloud Ops Works LLC - https://cloudops.works/
#     Find us on:
#       GitHub: https://github.com/cloudopsworks
#       WebSite: https://cloudops.works
#     Distributed Under Apache v2.0 License
#

# settings:                               # (Optional) Settings for OpenRouter workspace API key management
#   rotation_lambda: "rotate-openrouter-key" # (Optional) Existing module-wide Lambda name or ARN; when set, Lambda owns creation and rotation of enrolled OpenRouter keys
#   rotation_period_days: 30             # (Optional) Rotation interval in whole days, 1-1000. Default: 30; ignored with cron. 1000 uses legacy scheduling without a window override
#   rotation_window_hours: 1             # (Optional) Rotation window in whole hours, 1-23. Omit for the AWS default
#   rotation_cron_expression: "cron(0 3 1 * ? *)" # (Optional) AWS cron at one UTC hour; overrides the interval. Default: null
#   workspaces:                           # (Optional) Map of OpenRouter workspaces keyed by a logical name
#     engineering:                        # Logical key used to identify the workspace in this module
#       workspace_id: "ws_1234567890"    # (Optional) OpenRouter workspace UUID. Mutually exclusive with workspace_name and workspace_slug
#       workspace_name: "Engineering"    # (Optional) OpenRouter workspace name resolved via the provider workspace data source. Mutually exclusive with workspace_id and workspace_slug
#       workspace_slug: "engineering"    # (Optional) OpenRouter workspace slug resolved via the provider workspace data source. Mutually exclusive with workspace_id and workspace_name
#       api_keys:                         # (Optional) Map of API key configurations keyed by logical name
#         backend-service:
#           name_prefix: "backend"       # (Optional) Name prefix; final name = name_prefix + "-" + system_name
#           name: "fixed-name"           # (Optional) Fixed name for the API key (mutually exclusive with name_prefix)
#           limit: 250                    # (Optional) Spending limit in USD
#           limit_reset: "monthly"       # (Optional) Reset interval. Valid values: daily, weekly, monthly
#           include_byok_in_limit: true   # (Optional) Whether BYOK usage counts toward the limit
#           disabled: false               # (Optional) Whether the key is disabled. Default: provider/API default; rotation Lambda applies it via PATCH after Create
#           expires_at: "2026-12-31T23:59:59Z" # (Optional) UTC ISO-8601 expiration timestamp
#           creator_user_id: "user_123"  # (Optional) OpenRouter organization member ID to set as creator
#           secret:                       # (Optional) AWS Secrets Manager configuration for storing the API key
#             name_prefix: "backend"     # (Optional) Secret name prefix; final name = name_prefix + "-" + system_name
#             name: "fixed-secret"       # (Optional) Fixed secret name (mutually exclusive with secret.name_prefix)
#             path: "/custom/path"       # (Optional) Secret path prefix. Default: /<org_unit>/<env_name>/<env_type>/<workspace_key>
#             plain: false                # (Optional, deprecated) Must remain false; every secret stores JSON with api_key, api_key_id, name, and workspace_id, even without rotation
#             description: "..."         # (Optional) Human-readable description for the Secrets Manager secret
#             rotation_enabled: true      # (Optional) Let the module-wide Lambda own this key's lifecycle. Default: true; false opts out (not recommended)
variable "settings" {
  description = "Settings for OpenRouter workspace API key management and AWS Secrets Manager persistence"
  type = object({
    rotation_lambda          = optional(string)
    rotation_period_days     = optional(number, 30) # (Optional) Whole-day interval, 1-1000; 1000 uses legacy scheduling without a window override. Ignored with cron. Default: 30
    rotation_window_hours    = optional(number)     # (Optional) Whole-hour window, 1-23. Omit for the AWS default
    rotation_cron_expression = optional(string)     # (Optional) AWS cron at one UTC hour; overrides the interval. Default: null
    workspaces = optional(map(object({
      workspace_id   = optional(string)
      workspace_name = optional(string)
      workspace_slug = optional(string)
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
          name_prefix      = optional(string)
          name             = optional(string)
          path             = optional(string)
          plain            = optional(bool, false)
          description      = optional(string)
          rotation_enabled = optional(bool, true)
        }), {})
      })), {})
    })), {})
  })
  default = {}

  validation {
    condition = alltrue([
      for workspace in values(try(var.settings.workspaces, {})) : length(compact([
        try(workspace.workspace_id, null),
        try(workspace.workspace_name, null),
        try(workspace.workspace_slug, null)
      ])) <= 1
    ])
    error_message = "Each settings.workspaces.<workspace> entry may set at most one of workspace_id, workspace_name, or workspace_slug."
  }

  validation {
    condition = alltrue([
      for workspace in values(try(var.settings.workspaces, {})) : (
        try(workspace.workspace_id, null) == null || trimspace(workspace.workspace_id) != ""
      )
    ])
    error_message = "Each explicitly set settings.workspaces.<workspace>.workspace_id must be nonempty."
  }

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

  validation {
    condition = var.settings.rotation_lambda == null ? true : (
      can(regex("^arn:[^:]+:lambda:[^:]+:[0-9]{12}:function:[^:]+(?::[^:]+)?$", var.settings.rotation_lambda)) ||
      can(regex("^[A-Za-z0-9_-]{1,64}$", var.settings.rotation_lambda))
    )
    error_message = "settings.rotation_lambda must be a Lambda function name (1-64 letters, numbers, underscores or hyphens) or full function ARN."
  }

  validation {
    condition = (
      var.settings.rotation_period_days >= 1 &&
      var.settings.rotation_period_days <= 1000 &&
      var.settings.rotation_period_days == floor(var.settings.rotation_period_days)
    )
    error_message = "settings.rotation_period_days must be a whole number from 1 through 1000."
  }

  validation {
    condition = (
      var.settings.rotation_period_days != 1000 ||
      var.settings.rotation_cron_expression != null ||
      var.settings.rotation_window_hours == null
    )
    error_message = "A window override requires an AWS rate interval of at most 999 days or a cron expression. Omit settings.rotation_window_hours to keep legacy 1000-day scheduling."
  }

  validation {
    condition = var.settings.rotation_window_hours == null ? true : (
      var.settings.rotation_window_hours >= 1 &&
      var.settings.rotation_window_hours <= 23 &&
      var.settings.rotation_window_hours == floor(var.settings.rotation_window_hours)
    )
    error_message = "settings.rotation_window_hours must be a whole number from 1 through 23."
  }

  validation {
    # AWS validates the calendar fields; the module checks the UTC window.
    condition = var.settings.rotation_cron_expression == null ? true : try(
      tonumber(regex("^cron\\(0\\s+([01]?[0-9]|2[0-3])\\s+[^\\s()]+\\s+[^\\s()]+\\s+[^\\s()]+\\s+[^\\s()]+\\)$", trimspace(var.settings.rotation_cron_expression))[0]) + coalesce(var.settings.rotation_window_hours, 0) <= 24,
      false
    )
    error_message = "settings.rotation_cron_expression must be a six-field AWS cron expression with minute 0 and one UTC hour (0-23); the rotation window must not extend past midnight."
  }

  validation {
    condition = var.settings.rotation_lambda == null || var.settings.rotation_cron_expression == null ? true : alltrue(flatten([
      for workspace in values(var.settings.workspaces) : [
        for api_key in values(workspace.api_keys) : !api_key.secret.rotation_enabled || api_key.expires_at != null
      ]
    ]))
    error_message = "Each rotating OpenRouter key must set expires_at when settings.rotation_cron_expression is configured."
  }

  validation {
    condition = alltrue(flatten([
      for workspace in values(var.settings.workspaces) : [
        for api_key in values(workspace.api_keys) : !api_key.secret.plain
      ]
    ]))
    error_message = "settings.workspaces.<workspace>.api_keys.<key>.secret.plain must be false; every secret stores api_key, api_key_id, name, and workspace_id as JSON regardless of rotation."
  }
}
