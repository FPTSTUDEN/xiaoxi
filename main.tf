terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
    }
  }
}

provider "azurerm" {
  features {}
}

provider "azapi" {}

data "azurerm_client_config" "current" {}

# ============================================================
# RESOURCE GROUP
# ============================================================
resource "azurerm_resource_group" "siyuan" {
  name     = var.resource_group_name
  location = var.location
}

# ============================================================
# STORAGE ACCOUNT (Hot / LRS) with Azure Files share
# ============================================================
resource "azurerm_storage_account" "siyuan" {
  name                     = var.storage_account_name
  resource_group_name      = azurerm_resource_group.siyuan.name
  location                 = azurerm_resource_group.siyuan.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  access_tier              = "Hot"
  #   enable_https_traffic_only = true

  # Required for large file share (up to 100 TiB) [citation:3]
  large_file_share_enabled = true

  tags = var.tags
}

# Azure Files share for SiYuan workspace persistence [citation:20]
resource "azurerm_storage_share" "siyuan_workspace" {
  name               = "siyuan-workspace"
  storage_account_id = azurerm_storage_account.siyuan.id
  quota              = 10 # GB

  access_tier = "Cool" # Cost-effective for infrequent access
}

# ============================================================
# AZURE AI FOUNDRY WORKSPACE DEPENDENCIES
# ============================================================
resource "azurerm_key_vault" "foundry" {
  name                       = "${var.project_name}-kv"
  location                   = azurerm_resource_group.siyuan.location
  resource_group_name        = azurerm_resource_group.siyuan.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
  rbac_authorization_enabled = true
  tags                       = var.tags
}

resource "azurerm_application_insights" "foundry" {
  name                = "${var.project_name}-foundry-ai"
  location            = azurerm_resource_group.siyuan.location
  resource_group_name = azurerm_resource_group.siyuan.name
  application_type    = "web"
  retention_in_days   = 30
  tags                = var.tags
}

resource "azurerm_machine_learning_workspace" "foundry" {
  name                          = "${var.project_name}-foundry"
  location                      = azurerm_resource_group.siyuan.location
  resource_group_name           = azurerm_resource_group.siyuan.name
  application_insights_id       = azurerm_application_insights.foundry.id
  key_vault_id                  = azurerm_key_vault.foundry.id
  storage_account_id            = azurerm_storage_account.siyuan.id
  sku_name                      = "Basic"
  public_network_access_enabled = true
  identity {
    type = "SystemAssigned"
  }
  tags = var.tags
}

# ============================================================
# LOG ANALYTICS (required for Container Apps Environment logging) [citation:7]
# ============================================================
resource "azurerm_log_analytics_workspace" "siyuan" {
  name                = "${var.project_name}-logs"
  location            = azurerm_resource_group.siyuan.location
  resource_group_name = azurerm_resource_group.siyuan.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

# ============================================================
# CONTAINER APPS ENVIRONMENT
# ============================================================
resource "azurerm_container_app_environment" "siyuan" {
  name                       = "${var.project_name}-env"
  location                   = azurerm_resource_group.siyuan.location
  resource_group_name        = azurerm_resource_group.siyuan.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.siyuan.id

  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }


  tags = var.tags
}

# ============================================================
# STORAGE MOUNT FOR CONTAINER APPS ENVIRONMENT
# ============================================================
resource "azurerm_container_app_environment_storage" "siyuan" {
  name                         = "siyuan-storage"
  container_app_environment_id = azurerm_container_app_environment.siyuan.id
  account_name                 = azurerm_storage_account.siyuan.name
  share_name                   = azurerm_storage_share.siyuan_workspace.name
  access_key                   = azurerm_storage_account.siyuan.primary_access_key
  access_mode                  = "ReadWrite"
}

# ============================================================
# AZURE AI FOUNDRY SERVERLESS MODEL ENDPOINT
# ============================================================
resource "azapi_resource" "serverless_endpoint" {
  type      = "Microsoft.MachineLearningServices/workspaces/serverlessEndpoints@2024-04-01"
  name      = var.serverless_endpoint_name
  parent_id = azurerm_machine_learning_workspace.foundry.id
  location  = azurerm_resource_group.siyuan.location
  tags      = var.tags

  body = {
    properties = {
      authMode = "Key"
      modelSettings = {
        modelId = var.serverless_model_id
      }
    }
    sku = {
      name = "Standard"
    }
  }
}

resource "azapi_resource_action" "serverless_endpoint_keys" {
  type                   = "Microsoft.MachineLearningServices/workspaces/serverlessEndpoints@2024-04-01"
  resource_id            = azapi_resource.serverless_endpoint.id
  action                 = "listKeys"
  method                 = "POST"
  response_export_values = ["primaryKey"]
}

# ============================================================
# CONTAINER APP (SiYuan)
# ============================================================
resource "azurerm_container_app" "siyuan" {
  name                         = "${var.project_name}-app"
  container_app_environment_id = azurerm_container_app_environment.siyuan.id
  resource_group_name          = azurerm_resource_group.siyuan.name
  revision_mode                = "Single"

  # Secrets for auth code and Foundry serverless endpoint key.
  secret {
    name  = "siyuan-auth-code"
    value = var.siyuan_auth_code
  }

  secret {
    name  = "foundry-endpoint-key"
    value = jsondecode(azapi_resource_action.serverless_endpoint_keys.output).primaryKey
  }

  # Ingress configuration
  ingress {
    external_enabled = true
    target_port      = 6806

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  # Container template
  template {
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas

    # Volume definition referencing the environment storage [citation:20][citation:30]
    volume {
      name         = "siyuan-workspace"
      storage_name = azurerm_container_app_environment_storage.siyuan.name
      storage_type = "AzureFile"
    }

    container {
      name   = "siyuan"
      image  = "b3log/siyuan:latest"
      cpu    = var.container_cpu
      memory = var.container_memory

      # Command to start SiYuan server (required since v3.7.0)
      command = ["serve"]
      args    = ["--workspace=/siyuan/workspace/", "--accessAuthCode=${var.siyuan_auth_code}"]

      # Volume mount
      volume_mounts {
        name = "siyuan-workspace"
        path = "/siyuan/workspace"
      }

      # Environment variables
      env {
        name  = "PUID"
        value = "1000"
      }

      env {
        name  = "PGID"
        value = "1000"
      }

      env {
        name  = "TZ"
        value = var.timezone
      }

      # Azure AI Foundry serverless endpoint configuration.
      env {
        name  = "AZURE_AI_ENDPOINT"
        value = jsondecode(azapi_resource.serverless_endpoint.output).properties.inferenceEndpoint.uri
      }

      env {
        name        = "AZURE_AI_API_KEY"
        secret_name = "foundry-endpoint-key"
      }

      env {
        name  = "AZURE_AI_MODEL"
        value = var.serverless_model_id
      }
    }
  }

  tags = var.tags

  depends_on = [
    azurerm_container_app_environment_storage.siyuan,
    azapi_resource.serverless_endpoint
  ]
}