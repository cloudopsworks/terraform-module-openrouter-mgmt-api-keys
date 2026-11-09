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

resource "aws_secretsmanager_secret" "this" {
  for_each = local.api_keys

  name        = "${local.secret_paths[each.key]}/${local.secret_names[each.key]}"
  description = local.secret_descriptions[each.key]
  tags        = local.all_tags
}

resource "aws_secretsmanager_secret_version" "this" {
  for_each = local.api_keys

  secret_id = aws_secretsmanager_secret.this[each.key].id
  secret_string = local.secret_plain[each.key] ? (
    openrouter_api_key.this[each.key].key
    ) : (
    jsonencode({
      api_key      = openrouter_api_key.this[each.key].key
      api_key_id   = openrouter_api_key.this[each.key].id
      workspace_id = openrouter_api_key.this[each.key].workspace_id
    })
  )
}

data "aws_lambda_function" "rotation" {
  count = var.settings.rotation_lambda == null ? 0 : startswith(var.settings.rotation_lambda, "arn:") ? 0 : 1

  function_name = var.settings.rotation_lambda
}

resource "aws_secretsmanager_secret_rotation" "this" {
  for_each = {
    for key, api_key in local.api_keys : key => api_key
    if var.settings.rotation_lambda != null && api_key.secret.rotation_enabled
  }

  # Referencing the initial version ensures the secret value exists before rotation is enabled.
  secret_id           = aws_secretsmanager_secret_version.this[each.key].secret_id
  rotation_lambda_arn = startswith(var.settings.rotation_lambda, "arn:") ? var.settings.rotation_lambda : data.aws_lambda_function.rotation[0].arn

  rotation_rules {
    automatically_after_days = var.settings.rotation_period_days
  }

  depends_on = [aws_secretsmanager_secret_version.this]
}
