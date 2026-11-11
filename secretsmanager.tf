##
# (c) 2021-2026
#     Cloud Ops Works LLC - https://cloudops.works/
#     Find us on:
#       GitHub: https://github.com/cloudopsworks
#       WebSite: https://cloudops.works
#     Distributed Under Apache v2.0 License
#
# Stores OpenRouter API keys in AWS Secrets Manager.
# Secret path: <secret_path>/<secret_name>
# The key value is only returned on create by the OpenRouter management API.

locals {
  # AWS accepts 1000 days only via the legacy days field, not rate().
  rotation_uses_legacy_period = var.settings.rotation_cron_expression == null && var.settings.rotation_period_days == 1000
  rotation_schedule_expression = local.rotation_uses_legacy_period ? null : (
    var.settings.rotation_cron_expression != null
    ? join(" ", regexall("\\S+", var.settings.rotation_cron_expression))
    : "rate(${var.settings.rotation_period_days} ${var.settings.rotation_period_days == 1 ? "day" : "days"})"
  )

  rotating_api_keys = {
    for key, api_key in local.api_keys : key => api_key
    if var.settings.rotation_lambda != null && api_key.secret.rotation_enabled
  }

  non_rotating_api_keys = {
    for key, api_key in local.api_keys : key => api_key
    if var.settings.rotation_lambda == null || !api_key.secret.rotation_enabled
  }

  non_rotating_secret_payloads = {
    for key, api_key in openrouter_api_key.this : key => jsonencode({
      api_key      = api_key.key
      api_key_id   = api_key.id
      name         = api_key.name
      workspace_id = api_key.workspace_id
    })
  }

  rotation_bootstrap_payloads = {
    for key, api_key in local.rotating_api_keys : key => jsonencode({
      api_key      = null
      api_key_id   = "__CREATE_NEW__"
      name         = local.api_key_names[key]
      workspace_id = api_key.workspace_id
    })
  }

  rotation_config_payloads = {
    for key, api_key in local.rotating_api_keys : key => jsonencode({
      schema_version        = 1
      name                  = local.api_key_names[key]
      workspace_id          = api_key.workspace_id
      limit                 = api_key.limit
      limit_reset           = api_key.limit_reset
      include_byok_in_limit = api_key.include_byok_in_limit
      disabled              = api_key.disabled
      expires_at            = api_key.expires_at
      creator_user_id       = api_key.creator_user_id
    })
  }
}

resource "aws_secretsmanager_secret" "this" {
  for_each = local.api_keys

  name        = "${local.secret_paths[each.key]}/${local.secret_names[each.key]}"
  description = local.secret_descriptions[each.key]
  tags        = local.all_tags

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

resource "aws_secretsmanager_secret_version" "this" {
  for_each = local.rotating_api_keys

  secret_id      = aws_secretsmanager_secret.this[each.key].id
  secret_string  = local.rotation_bootstrap_payloads[each.key]
  version_stages = ["TFBOOTSTRAP"]

  # The rotation Lambda owns AWSCURRENT after bootstrap. Ignore later payload and
  # staging-label drift so ordinary external rotation does not restore this version.
  lifecycle {
    ignore_changes = [secret_string, version_stages]
  }
}

resource "aws_secretsmanager_secret_version" "rotation_config" {
  for_each = local.rotating_api_keys

  # The bootstrap version must be AWSCURRENT before this custom-stage-only
  # configuration version is written to the same secret.
  secret_id      = aws_secretsmanager_secret_version.this[each.key].secret_id
  secret_string  = local.rotation_config_payloads[each.key]
  version_stages = ["TFCONFIG"]
}

resource "aws_secretsmanager_secret_version" "non_rotating" {
  for_each = local.non_rotating_api_keys

  secret_id     = aws_secretsmanager_secret.this[each.key].id
  secret_string = local.non_rotating_secret_payloads[each.key]
}

data "aws_lambda_function" "rotation" {
  count = var.settings.rotation_lambda == null ? 0 : startswith(var.settings.rotation_lambda, "arn:") ? 0 : 1

  function_name = var.settings.rotation_lambda
}

resource "aws_secretsmanager_secret_rotation" "this" {
  for_each = local.rotating_api_keys

  # The config version depends on bootstrap creation; both must exist before
  # Secrets Manager invokes the rotation Lambda.
  secret_id           = aws_secretsmanager_secret_version.rotation_config[each.key].secret_id
  rotation_lambda_arn = startswith(var.settings.rotation_lambda, "arn:") ? var.settings.rotation_lambda : data.aws_lambda_function.rotation[0].arn

  rotation_rules {
    automatically_after_days = local.rotation_uses_legacy_period ? var.settings.rotation_period_days : null
    schedule_expression      = local.rotation_schedule_expression
    duration                 = var.settings.rotation_window_hours == null ? null : "${var.settings.rotation_window_hours}h"
  }

  depends_on = [aws_secretsmanager_secret_version.rotation_config]
}
