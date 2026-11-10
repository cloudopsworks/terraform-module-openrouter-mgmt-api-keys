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
  rotating_api_keys = {
    for key, api_key in local.api_keys : key => api_key
    if var.settings.rotation_lambda != null && api_key.secret.rotation_enabled
  }

  non_rotating_api_keys = {
    for key, api_key in local.api_keys : key => api_key
    if var.settings.rotation_lambda == null || !api_key.secret.rotation_enabled
  }

  secret_payloads = {
    for key, api_key in openrouter_api_key.this : key => jsonencode({
      api_key      = api_key.key
      api_key_id   = api_key.id
      name         = api_key.name
      workspace_id = api_key.workspace_id
    })
  }
}

resource "aws_secretsmanager_secret" "this" {
  for_each = local.api_keys

  name        = "${local.secret_paths[each.key]}/${local.secret_names[each.key]}"
  description = local.secret_descriptions[each.key]
  tags        = local.all_tags
}

resource "aws_secretsmanager_secret_version" "this" {
  for_each = local.rotating_api_keys

  secret_id      = aws_secretsmanager_secret.this[each.key].id
  secret_string  = local.secret_payloads[each.key]
  version_stages = ["TFBOOTSTRAP"]

  # The rotation Lambda owns AWSCURRENT after bootstrap. Ignore later payload and
  # staging-label drift so ordinary external rotation does not restore this version.
  lifecycle {
    ignore_changes = [secret_string, version_stages]
  }
}

resource "aws_secretsmanager_secret_version" "non_rotating" {
  for_each = local.non_rotating_api_keys

  secret_id     = aws_secretsmanager_secret.this[each.key].id
  secret_string = local.secret_payloads[each.key]
}

data "aws_lambda_function" "rotation" {
  count = var.settings.rotation_lambda == null ? 0 : startswith(var.settings.rotation_lambda, "arn:") ? 0 : 1

  function_name = var.settings.rotation_lambda
}

resource "aws_secretsmanager_secret_rotation" "this" {
  for_each = local.rotating_api_keys

  # Referencing the initial version ensures the secret value exists before rotation is enabled.
  secret_id           = aws_secretsmanager_secret_version.this[each.key].secret_id
  rotation_lambda_arn = startswith(var.settings.rotation_lambda, "arn:") ? var.settings.rotation_lambda : data.aws_lambda_function.rotation[0].arn

  rotation_rules {
    automatically_after_days = var.settings.rotation_period_days
  }

  depends_on = [aws_secretsmanager_secret_version.this]
}
