## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.35 |
| <a name="requirement_openrouter"></a> [openrouter](#requirement\_openrouter) | ~> 0.1 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 6.35 |
| <a name="provider_openrouter"></a> [openrouter](#provider\_openrouter) | ~> 0.1 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_tags"></a> [tags](#module\_tags) | cloudopsworks/tags/local | 1.0.10 |

## Resources

| Name | Type |
|------|------|
| [aws_secretsmanager_secret.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret_version.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [openrouter_api_key.this](https://registry.terraform.io/providers/cloudopsworks/openrouter/latest/docs/resources/api_key) | resource |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [openrouter_workspaces.lookup](https://registry.terraform.io/providers/cloudopsworks/openrouter/latest/docs/data-sources/workspaces) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_extra_tags"></a> [extra\_tags](#input\_extra\_tags) | Extra tags to add to the resources | `map(string)` | `{}` | no |
| <a name="input_is_hub"></a> [is\_hub](#input\_is\_hub) | Is this a hub or spoke configuration? | `bool` | `false` | no |
| <a name="input_org"></a> [org](#input\_org) | Organization details | <pre>object({<br/>    organization_name = string<br/>    organization_unit = string<br/>    environment_type  = string<br/>    environment_name  = string<br/>  })</pre> | n/a | yes |
| <a name="input_settings"></a> [settings](#input\_settings) | Settings for OpenRouter workspace API key management and AWS Secrets Manager persistence | <pre>object({<br/>    workspaces = optional(map(object({<br/>      workspace_id   = optional(string)<br/>      workspace_name = optional(string)<br/>      workspace_slug = optional(string)<br/>      api_keys = optional(map(object({<br/>        name_prefix           = optional(string)<br/>        name                  = optional(string)<br/>        limit                 = optional(number)<br/>        limit_reset           = optional(string)<br/>        include_byok_in_limit = optional(bool)<br/>        disabled              = optional(bool)<br/>        expires_at            = optional(string)<br/>        creator_user_id       = optional(string)<br/>        secret = optional(object({<br/>          name_prefix = optional(string)<br/>          name        = optional(string)<br/>          path        = optional(string)<br/>          plain       = optional(bool, false)<br/>          description = optional(string)<br/>        }), {})<br/>      })), {})<br/>    })), {})<br/>  })</pre> | `{}` | no |
| <a name="input_spoke_def"></a> [spoke\_def](#input\_spoke\_def) | Spoke ID Number, must be a 3 digit number | `string` | `"001"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_api_key_ids"></a> [api\_key\_ids](#output\_api\_key\_ids) | Map of OpenRouter API key IDs keyed by '<workspace\_key>/<api\_key\_key>' |
| <a name="output_api_key_labels"></a> [api\_key\_labels](#output\_api\_key\_labels) | Map of server-generated OpenRouter API key labels keyed by '<workspace\_key>/<api\_key\_key>' |
| <a name="output_secret_arns"></a> [secret\_arns](#output\_secret\_arns) | Map of AWS Secrets Manager secret ARNs holding OpenRouter API keys, keyed by '<workspace\_key>/<api\_key\_key>' |
| <a name="output_secret_names"></a> [secret\_names](#output\_secret\_names) | Map of AWS Secrets Manager secret names holding OpenRouter API keys, keyed by '<workspace\_key>/<api\_key\_key>' |
