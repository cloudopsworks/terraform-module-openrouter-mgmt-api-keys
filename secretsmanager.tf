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
    jsonencode({ api_key = openrouter_api_key.this[each.key].key })
  )
}
