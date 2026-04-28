##
# (c) 2021-2026
#     Cloud Ops Works LLC - https://cloudops.works/
#     Find us on:
#       GitHub: https://github.com/cloudopsworks
#       WebSite: https://cloudops.works
#     Distributed Under Apache v2.0 License
#

output "api_key_ids" {
  description = "Map of OpenRouter API key IDs keyed by '<workspace_key>/<api_key_key>'"
  value = {
    for k, v in openrouter_api_key.this : k => v.id
  }
}

output "api_key_labels" {
  description = "Map of server-generated OpenRouter API key labels keyed by '<workspace_key>/<api_key_key>'"
  value = {
    for k, v in openrouter_api_key.this : k => v.label
  }
}

output "secret_arns" {
  description = "Map of AWS Secrets Manager secret ARNs holding OpenRouter API keys, keyed by '<workspace_key>/<api_key_key>'"
  value = {
    for k, v in aws_secretsmanager_secret.this : k => v.arn
  }
}

output "secret_names" {
  description = "Map of AWS Secrets Manager secret names holding OpenRouter API keys, keyed by '<workspace_key>/<api_key_key>'"
  value = {
    for k, v in aws_secretsmanager_secret.this : k => v.name
  }
}
