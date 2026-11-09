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
      workspaces = {
        engineering = {
          workspace_id = "ws_example"
          api_keys = {
            backend = {
              name = "backend"
              secret = {
                rotation_period_days = 60
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
    condition     = length(aws_secretsmanager_secret.this) == 2 && length(aws_secretsmanager_secret_rotation.this) == 0 && length(data.aws_lambda_function.rotation) == 0
    error_message = "No key may create a rotation schedule without the module-wide Lambda."
  }
}

run "rotation_uses_configured_period" {
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
                rotation_period_days = 45
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
      length(aws_secretsmanager_secret_rotation.this) == 2 &&
      length(data.aws_lambda_function.rotation) == 0 &&
      aws_secretsmanager_secret_rotation.this["engineering/backend"].rotation_rules[0].automatically_after_days == 45 &&
      aws_secretsmanager_secret_rotation.this["engineering/reporting"].rotation_rules[0].automatically_after_days == 30 &&
      aws_secretsmanager_secret_rotation.this["engineering/backend"].rotation_lambda_arn == "arn:aws:lambda:us-east-1:123456789012:function:rotate-openrouter" &&
      aws_secretsmanager_secret_rotation.this["engineering/reporting"].rotation_lambda_arn == "arn:aws:lambda:us-east-1:123456789012:function:rotate-openrouter"
    )
    error_message = "A module-wide Lambda must rotate every key with each key's configured interval."
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

run "invalid_period_is_rejected" {
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
                rotation_period_days = 0
              }
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
      workspaces = {
        engineering = {
          workspace_id = "ws_example"
          api_keys = {
            backend = {
              name = "backend"
              secret = {
                rotation_period_days = 1.5
              }
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
