mock_provider "aws" {
  mock_data "aws_region" {
    defaults = {
      region = "us-east-1"
    }
  }

  mock_data "aws_lambda_function" {
    defaults = {
      arn = "arn:aws:lambda:us-east-1:123456789012:function:rotate-openrouter"
    }
  }
}

mock_provider "openrouter" {}

variables {
  org = {
    organization_name = "example"
    organization_unit = "platform"
    environment_type  = "production"
    environment_name  = "prod"
  }
}

run "rotation_disabled_without_lambda" {
  command = plan

  variables {
    settings = {
      rotation_period_days = 60
      workspaces = {
        engineering = {
          workspace_id = "ws_example"
          api_keys = {
            backend = {
              name = "backend"
            }
            reporting = {
              name = "reporting"
            }
          }
        }
      }
    }
  }

  assert {
    condition     = length(openrouter_api_key.this) == 2 && length(aws_secretsmanager_secret.this) == 2 && length(aws_secretsmanager_secret_version.this) == 0 && length(aws_secretsmanager_secret_version.rotation_config) == 0 && length(aws_secretsmanager_secret_version.non_rotating) == 2 && length(aws_secretsmanager_secret_rotation.this) == 0 && length(data.aws_lambda_function.rotation) == 0
    error_message = "Without the module-wide Lambda, every key must have a Terraform-updated version and no rotation schedule."
  }
}

run "rotation_uses_configured_period" {
  command = plan

  variables {
    settings = {
      rotation_lambda      = "arn:aws:lambda:us-east-1:123456789012:function:rotate-openrouter"
      rotation_period_days = 45
      workspaces = {
        engineering = {
          workspace_id = "ws_example"
          api_keys = {
            backend = {
              name = "backend"
            }
            reporting = {
              name = "reporting"
            }
          }
        }
      }
    }
  }

  assert {
    condition = (
      length(openrouter_api_key.this) == 0 &&
      length(aws_secretsmanager_secret_version.rotation_config) == 2 &&
      length(aws_secretsmanager_secret_rotation.this) == 2 &&
      length(data.aws_lambda_function.rotation) == 0 &&
      aws_secretsmanager_secret_rotation.this["engineering/backend"].rotation_rules[0].automatically_after_days == 45 &&
      aws_secretsmanager_secret_rotation.this["engineering/reporting"].rotation_rules[0].automatically_after_days == 45 &&
      aws_secretsmanager_secret_rotation.this["engineering/backend"].rotation_lambda_arn == "arn:aws:lambda:us-east-1:123456789012:function:rotate-openrouter" &&
      aws_secretsmanager_secret_rotation.this["engineering/reporting"].rotation_lambda_arn == "arn:aws:lambda:us-east-1:123456789012:function:rotate-openrouter"
    )
    error_message = "A module-wide Lambda must rotate every key with the same configured interval."
  }
}

run "rotation_defaults_to_30_days" {
  command = plan

  variables {
    settings = {
      rotation_lambda = "arn:aws:lambda:us-east-1:123456789012:function:rotate-openrouter"
      workspaces = {
        engineering = {
          workspace_id = "ws_example"
          api_keys = {
            backend = {
              name = "backend"
            }
          }
        }
      }
    }
  }

  assert {
    condition     = aws_secretsmanager_secret_rotation.this["engineering/backend"].rotation_rules[0].automatically_after_days == 30
    error_message = "Rotation must default to a 30-day interval when the global Lambda is configured."
  }
}

run "rotation_resolves_lambda_name" {
  command = plan

  variables {
    settings = {
      rotation_lambda = "rotate-openrouter"
      workspaces = {
        engineering = {
          workspace_id = "ws_example"
          api_keys = {
            backend = {
              name = "backend"
            }
          }
        }
      }
    }
  }

  assert {
    condition = (
      length(data.aws_lambda_function.rotation) == 1 &&
      length(aws_secretsmanager_secret_rotation.this) == 1 &&
      aws_secretsmanager_secret_rotation.this["engineering/backend"].rotation_lambda_arn == data.aws_lambda_function.rotation[0].arn
    )
    error_message = "A Lambda name must be resolved to its ARN before configuring rotation."
  }
}

run "rotation_opt_out_is_per_key" {
  command = plan

  variables {
    settings = {
      rotation_lambda = "arn:aws:lambda:us-east-1:123456789012:function:rotate-openrouter"
      workspaces = {
        engineering = {
          workspace_id = "ws_example"
          api_keys = {
            backend = {
              name = "backend"
              secret = {
                rotation_enabled = false
              }
            }
            reporting = {
              name = "reporting"
            }
          }
        }
      }
    }
  }

  assert {
    condition = (
      length(openrouter_api_key.this) == 1 &&
      length(aws_secretsmanager_secret.this) == 2 &&
      length(aws_secretsmanager_secret_version.this) == 1 &&
      length(aws_secretsmanager_secret_version.rotation_config) == 1 &&
      length(aws_secretsmanager_secret_version.non_rotating) == 1 &&
      length(aws_secretsmanager_secret_rotation.this) == 1 &&
      contains(keys(aws_secretsmanager_secret_rotation.this), "engineering/reporting") &&
      !contains(keys(aws_secretsmanager_secret_rotation.this), "engineering/backend")
    )
    error_message = "Opting out one key must not disable rotation for other keys."
  }
}

run "json_secret_tracks_every_key_without_rotation" {
  command = apply

  variables {
    settings = {
      workspaces = {
        engineering = {
          workspace_id = "ws_engineering"
          api_keys = {
            backend = {
              name = "backend"
            }
          }
        }
        shared = {
          workspace_id = "ws_shared"
          api_keys = {
            reporting = {
              name = "reporting"
            }
          }
        }
      }
    }
  }

  assert {
    condition = alltrue([
      for key in ["engineering/backend", "shared/reporting"] : (
        length(keys(jsondecode(aws_secretsmanager_secret_version.non_rotating[key].secret_string))) == 4 &&
        jsondecode(aws_secretsmanager_secret_version.non_rotating[key].secret_string).api_key == openrouter_api_key.this[key].key &&
        jsondecode(aws_secretsmanager_secret_version.non_rotating[key].secret_string).api_key_id == openrouter_api_key.this[key].id &&
        jsondecode(aws_secretsmanager_secret_version.non_rotating[key].secret_string).name == openrouter_api_key.this[key].name &&
        jsondecode(aws_secretsmanager_secret_version.non_rotating[key].secret_string).workspace_id == openrouter_api_key.this[key].workspace_id
      )
      ]) && (
      jsondecode(aws_secretsmanager_secret_version.non_rotating["engineering/backend"].secret_string).workspace_id == "ws_engineering" &&
      jsondecode(aws_secretsmanager_secret_version.non_rotating["shared/reporting"].secret_string).workspace_id == "ws_shared"
    )
    error_message = "Without rotation, each JSON secret must contain its own API key, key ID, key name, and workspace ID."
  }
}

run "json_secret_tracks_every_key_with_rotation" {
  command = apply

  variables {
    settings = {
      rotation_lambda = "arn:aws:lambda:us-east-1:123456789012:function:rotate-openrouter"
      workspaces = {
        engineering = {
          workspace_id = "ws_engineering"
          api_keys = {
            backend = {
              name = "backend"
            }
            reporting = {
              name = "reporting"
              secret = {
                rotation_enabled = false
              }
            }
          }
        }
      }
    }
  }

  assert {
    condition = (
      length(openrouter_api_key.this) == 1 &&
      !contains(keys(openrouter_api_key.this), "engineering/backend") &&
      length(keys(jsondecode(aws_secretsmanager_secret_version.this["engineering/backend"].secret_string))) == 4 &&
      jsondecode(aws_secretsmanager_secret_version.this["engineering/backend"].secret_string).api_key == null &&
      jsondecode(aws_secretsmanager_secret_version.this["engineering/backend"].secret_string).api_key_id == "__CREATE_NEW__" &&
      jsondecode(aws_secretsmanager_secret_version.this["engineering/backend"].secret_string).name == "backend" &&
      jsondecode(aws_secretsmanager_secret_version.this["engineering/backend"].secret_string).workspace_id == "ws_engineering" &&
      contains(aws_secretsmanager_secret_version.this["engineering/backend"].version_stages, "TFBOOTSTRAP") &&
      contains(aws_secretsmanager_secret_version.rotation_config["engineering/backend"].version_stages, "TFCONFIG") &&
      length(keys(jsondecode(aws_secretsmanager_secret_version.rotation_config["engineering/backend"].secret_string))) == 9 &&
      jsondecode(aws_secretsmanager_secret_version.rotation_config["engineering/backend"].secret_string).schema_version == 1 &&
      jsondecode(aws_secretsmanager_secret_version.rotation_config["engineering/backend"].secret_string).name == "backend" &&
      jsondecode(aws_secretsmanager_secret_version.rotation_config["engineering/backend"].secret_string).workspace_id == "ws_engineering" &&
      jsondecode(aws_secretsmanager_secret_version.rotation_config["engineering/backend"].secret_string).limit == null &&
      jsondecode(aws_secretsmanager_secret_version.rotation_config["engineering/backend"].secret_string).disabled == null &&
      length(keys(jsondecode(aws_secretsmanager_secret_version.non_rotating["engineering/reporting"].secret_string))) == 4 &&
      jsondecode(aws_secretsmanager_secret_version.non_rotating["engineering/reporting"].secret_string).api_key == openrouter_api_key.this["engineering/reporting"].key &&
      jsondecode(aws_secretsmanager_secret_version.non_rotating["engineering/reporting"].secret_string).api_key_id == openrouter_api_key.this["engineering/reporting"].id &&
      jsondecode(aws_secretsmanager_secret_version.non_rotating["engineering/reporting"].secret_string).name == openrouter_api_key.this["engineering/reporting"].name &&
      jsondecode(aws_secretsmanager_secret_version.non_rotating["engineering/reporting"].secret_string).workspace_id == openrouter_api_key.this["engineering/reporting"].workspace_id &&
      length(aws_secretsmanager_secret_rotation.this) == 1 &&
      contains(keys(aws_secretsmanager_secret_rotation.this), "engineering/backend") &&
      length(output.api_key_ids) == 1 &&
      length(output.api_key_labels) == 1 &&
      length(output.rotation_secret_arns) == 1 &&
      length(output.rotation_config_version_ids) == 1
    )
    error_message = "Rotating keys must be Lambda-owned with a bootstrap marker and config stage; opted-out keys remain Terraform-owned."
  }
}

run "rotation_config_preserves_all_create_parameters" {
  command = apply

  variables {
    settings = {
      rotation_lambda = "arn:aws:lambda:us-east-1:123456789012:function:rotate-openrouter"
      workspaces = {
        engineering = {
          workspace_id = "ws_engineering"
          api_keys = {
            backend = {
              name_prefix           = "backend"
              limit                 = 0
              limit_reset           = "weekly"
              include_byok_in_limit = false
              disabled              = true
              expires_at            = "2026-12-31T23:59:59Z"
              creator_user_id       = "user_123"
            }
          }
        }
      }
    }
  }

  assert {
    condition = (
      length(openrouter_api_key.this) == 0 &&
      jsondecode(aws_secretsmanager_secret_version.rotation_config["engineering/backend"].secret_string).schema_version == 1 &&
      jsondecode(aws_secretsmanager_secret_version.rotation_config["engineering/backend"].secret_string).name == local.api_key_names["engineering/backend"] &&
      jsondecode(aws_secretsmanager_secret_version.rotation_config["engineering/backend"].secret_string).workspace_id == "ws_engineering" &&
      jsondecode(aws_secretsmanager_secret_version.rotation_config["engineering/backend"].secret_string).limit == 0 &&
      jsondecode(aws_secretsmanager_secret_version.rotation_config["engineering/backend"].secret_string).limit_reset == "weekly" &&
      jsondecode(aws_secretsmanager_secret_version.rotation_config["engineering/backend"].secret_string).include_byok_in_limit == false &&
      jsondecode(aws_secretsmanager_secret_version.rotation_config["engineering/backend"].secret_string).disabled == true &&
      jsondecode(aws_secretsmanager_secret_version.rotation_config["engineering/backend"].secret_string).expires_at == "2026-12-31T23:59:59Z" &&
      jsondecode(aws_secretsmanager_secret_version.rotation_config["engineering/backend"].secret_string).creator_user_id == "user_123"
    )
    error_message = "TFCONFIG must carry every resolved OpenRouter key parameter, including zero and false."
  }
}

run "rotation_seed_allows_provider_default_workspace" {
  command = apply

  variables {
    settings = {
      rotation_lambda = "arn:aws:lambda:us-east-1:123456789012:function:rotate-openrouter"
      workspaces = {
        default = {
          api_keys = {
            backend = {
              name = "backend"
            }
          }
        }
      }
    }
  }

  assert {
    condition = (
      length(openrouter_api_key.this) == 0 &&
      jsondecode(aws_secretsmanager_secret_version.this["default/backend"].secret_string).api_key_id == "__CREATE_NEW__" &&
      jsondecode(aws_secretsmanager_secret_version.this["default/backend"].secret_string).workspace_id == null &&
      jsondecode(aws_secretsmanager_secret_version.rotation_config["default/backend"].secret_string).workspace_id == null
    )
    error_message = "The Lambda bootstrap and config must preserve an omitted workspace selector as null."
  }
}

run "json_secret_tracks_provider_default_workspace" {
  command = apply

  variables {
    settings = {
      workspaces = {
        default = {
          api_keys = {
            backend = {
              name = "backend"
            }
          }
        }
      }
    }
  }

  assert {
    condition = (
      local.workspace_ids["default"] == null &&
      openrouter_api_key.this["default/backend"].workspace_id != null &&
      openrouter_api_key.this["default/backend"].workspace_id == jsondecode(aws_secretsmanager_secret_version.non_rotating["default/backend"].secret_string).workspace_id
    )
    error_message = "A key without a workspace selector must store the provider-returned workspace ID."
  }
}

run "empty_explicit_workspace_id_is_rejected" {
  command = plan

  variables {
    settings = {
      workspaces = {
        engineering = {
          workspace_id = ""
          api_keys = {
            backend = {
              name = "backend"
            }
          }
        }
      }
    }
  }

  expect_failures = [var.settings]
}

run "plain_secret_is_rejected_without_rotation" {
  command = plan

  variables {
    settings = {
      workspaces = {
        engineering = {
          workspace_id = "ws_example"
          api_keys = {
            backend = {
              name = "backend"
              secret = {
                plain = true
              }
            }
          }
        }
      }
    }
  }

  expect_failures = [var.settings]
}

run "plain_secret_is_rejected_when_enrolled_in_rotation" {
  command = plan

  variables {
    settings = {
      rotation_lambda = "arn:aws:lambda:us-east-1:123456789012:function:rotate-openrouter"
      workspaces = {
        engineering = {
          workspace_id = "ws_example"
          api_keys = {
            backend = {
              name = "backend"
              secret = {
                plain = true
              }
            }
          }
        }
      }
    }
  }

  expect_failures = [var.settings]
}

run "plain_secret_is_rejected_when_opted_out" {
  command = plan

  variables {
    settings = {
      rotation_lambda = "arn:aws:lambda:us-east-1:123456789012:function:rotate-openrouter"
      workspaces = {
        engineering = {
          workspace_id = "ws_example"
          api_keys = {
            backend = {
              name = "backend"
              secret = {
                plain            = true
                rotation_enabled = false
              }
            }
          }
        }
      }
    }
  }

  expect_failures = [var.settings]
}

run "invalid_period_is_rejected" {
  command = plan

  variables {
    settings = {
      rotation_lambda      = "arn:aws:lambda:us-east-1:123456789012:function:rotate-openrouter"
      rotation_period_days = 0
      workspaces = {
        engineering = {
          workspace_id = "ws_example"
          api_keys = {
            backend = {
              name = "backend"
            }
          }
        }
      }
    }
  }

  expect_failures = [var.settings]
}

run "fractional_period_is_rejected" {
  command = plan

  variables {
    settings = {
      rotation_period_days = 1.5
      workspaces = {
        engineering = {
          workspace_id = "ws_example"
          api_keys = {
            backend = {
              name = "backend"
            }
          }
        }
      }
    }
  }

  expect_failures = [var.settings]
}

run "period_above_limit_is_rejected" {
  command = plan

  variables {
    settings = {
      rotation_period_days = 1001
      workspaces = {
        engineering = {
          workspace_id = "ws_example"
          api_keys = {
            backend = {
              name = "backend"
            }
          }
        }
      }
    }
  }

  expect_failures = [var.settings]
}

run "invalid_lambda_arn_is_rejected" {
  command = plan

  variables {
    settings = {
      rotation_lambda = "arn:aws:lambda:invalid"
      workspaces = {
        engineering = {
          workspace_id = "ws_example"
          api_keys = {
            backend = {
              name = "backend"
            }
          }
        }
      }
    }
  }

  expect_failures = [var.settings]
}

run "invalid_lambda_name_is_rejected" {
  command = plan

  variables {
    settings = {
      rotation_lambda = "bad/name"
      workspaces = {
        engineering = {
          workspace_id = "ws_example"
          api_keys = {
            backend = {
              name = "backend"
            }
          }
        }
      }
    }
  }

  expect_failures = [var.settings]
}
