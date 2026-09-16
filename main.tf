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
resource "azurerm_application_insights" "foundry" {
  name                = "${var.project_name}-foundry-ai"
  location            = azurerm_resource_group.siyuan.location
  resource_group_name = azurerm_resource_group.siyuan.name
  application_type    = "web"
  retention_in_days   = 30
  tags                = var.tags
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
# CONTAINER APPS NETWORK (required for Azure Files storage)
# ============================================================
resource "azurerm_virtual_network" "siyuan" {
  name                = "${var.project_name}-vnet"
  location            = azurerm_resource_group.siyuan.location
  resource_group_name = azurerm_resource_group.siyuan.name
  address_space       = ["10.0.0.0/16"]
  tags                = var.tags
}

resource "azurerm_subnet" "container_apps" {
  name                 = "container-apps-infrastructure"
  resource_group_name  = azurerm_resource_group.siyuan.name
  virtual_network_name = azurerm_virtual_network.siyuan.name
  address_prefixes     = ["10.0.0.0/27"]

  delegation {
    name = "container-apps-delegation"

    service_delegation {
      name = "Microsoft.App/environments"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

# ============================================================
# CONTAINER APPS ENVIRONMENT
# ============================================================
resource "azurerm_container_app_environment" "siyuan" {
  name                       = "${var.project_name}-env"
  location                   = azurerm_resource_group.siyuan.location
  resource_group_name        = azurerm_resource_group.siyuan.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.siyuan.id
  infrastructure_subnet_id   = azurerm_subnet.container_apps.id

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
# AZURE OPENAI (AI Backend)
# ============================================================
resource "azurerm_cognitive_account" "openai" {
  name                = "${var.project_name}-openai"
  location            = azurerm_resource_group.siyuan.location
  resource_group_name = azurerm_resource_group.siyuan.name
  kind                = "OpenAI"
  sku_name            = "S0"
  custom_subdomain_name = var.project_name

  tags = var.tags
}

# Model deployment (e.g., gpt-4o-mini)
resource "azurerm_cognitive_deployment" "model" {
  name                 = var.openai_deployment_name
  cognitive_account_id = azurerm_cognitive_account.openai.id

  model {
    format  = var.openai_model_format
    name    = var.openai_model_name
    version = var.openai_model_version
  }

#   scale {
#     type     = "Standard"
#     capacity = var.openai_capacity
#   }
  sku {
    name = "GlobalStandard"
    # tier = "Standard"
    capacity = var.openai_capacity
  }
}

# ============================================================
# CONTAINER APP (SiYuan)
# ============================================================
resource "azurerm_container_app" "siyuan" {
  name                         = "${var.project_name}-app"
  container_app_environment_id = azurerm_container_app_environment.siyuan.id
  resource_group_name          = azurerm_resource_group.siyuan.name
  revision_mode                = "Single"

  # Secrets for auth code and OpenAI key [citation:5]
  secret {
    name  = "siyuan-auth-code"
    value = var.siyuan_auth_code
  }

  secret {
    name  = "azure-openai-key"
    value = azurerm_cognitive_account.openai.primary_access_key
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

      # The image entrypoint invokes the kernel, so pass its command and flags.
      args    = ["serve", "--workspace=/siyuan/workspace/"]

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
        name        = "SIYUAN_ACCESS_AUTH_CODE"
        secret_name = "siyuan-auth-code"
      }

      env {
        name  = "TZ"
        value = var.timezone
      }

      # AI configuration (for reference in SiYuan settings)
      env {
        name  = "AZURE_OPENAI_ENDPOINT"
        value = azurerm_cognitive_account.openai.endpoint
      }

      env {
        name        = "AZURE_OPENAI_API_KEY"
        secret_name = "azure-openai-key"
      }

      env {
        name  = "AZURE_OPENAI_DEPLOYMENT"
        value = azurerm_cognitive_deployment.model.name
      }

      env {
        name  = "AZURE_OPENAI_MODEL"
        value = var.openai_model_name
      }
    }
  }

  tags = var.tags

  depends_on = [
    azurerm_container_app_environment_storage.siyuan,
    azurerm_cognitive_deployment.model
  ]
}