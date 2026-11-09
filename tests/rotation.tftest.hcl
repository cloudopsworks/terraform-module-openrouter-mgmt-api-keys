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
    condition     = length(aws_secretsmanager_secret.this) == 2 && length(aws_secretsmanager_secret_rotation.this) == 0 && length(data.aws_lambda_function.rotation) == 0
    error_message = "No key may create a rotation schedule without the module-wide Lambda."
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
      length(aws_secretsmanager_secret.this) == 2 &&
      length(aws_secretsmanager_secret_rotation.this) == 1 &&
      contains(keys(aws_secretsmanager_secret_rotation.this), "engineering/reporting") &&
      !contains(keys(aws_secretsmanager_secret_rotation.this), "engineering/backend")
    )
    error_message = "Opting out one key must not disable rotation for other keys."
  }
}

run "json_secret_pairs_each_key_with_its_workspace" {
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
        length(keys(jsondecode(aws_secretsmanager_secret_version.this[key].secret_string))) == 3 &&
        jsondecode(aws_secretsmanager_secret_version.this[key].secret_string).api_key == openrouter_api_key.this[key].key &&
        jsondecode(aws_secretsmanager_secret_version.this[key].secret_string).api_key_id == openrouter_api_key.this[key].id &&
        jsondecode(aws_secretsmanager_secret_version.this[key].secret_string).workspace_id == openrouter_api_key.this[key].workspace_id
      )
      ]) && (
      jsondecode(aws_secretsmanager_secret_version.this["engineering/backend"].secret_string).workspace_id == "ws_engineering" &&
      jsondecode(aws_secretsmanager_secret_version.this["shared/reporting"].secret_string).workspace_id == "ws_shared"
    )
    error_message = "Each JSON secret must pair its own API key, OpenRouter key ID, and workspace ID."
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
      openrouter_api_key.this["default/backend"].workspace_id == jsondecode(aws_secretsmanager_secret_version.this["default/backend"].secret_string).workspace_id
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

run "plain_secret_stays_raw_without_rotation" {
  command = apply

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

  assert {
    condition     = aws_secretsmanager_secret_version.this["engineering/backend"].secret_string == openrouter_api_key.this["engineering/backend"].key && length(aws_secretsmanager_secret_rotation.this) == 0
    error_message = "A non-rotating plain secret must retain the raw API key string."
  }
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

run "plain_secret_is_allowed_when_opted_out" {
  command = apply

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

  assert {
    condition     = aws_secretsmanager_secret_version.this["engineering/backend"].secret_string == openrouter_api_key.this["engineering/backend"].key && length(aws_secretsmanager_secret_rotation.this) == 0
    error_message = "An opted-out plain secret must remain raw and unscheduled for rotation."
  }
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
