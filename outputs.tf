output "siyuan_url" {
  description = "Public URL of the SiYuan app"
  value       = "https://${azurerm_container_app.siyuan.ingress[0].fqdn}"
}

output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.siyuan.name
}

output "foundry_serverless_endpoint" {
  description = "Azure AI Foundry serverless endpoint URI"
  value       = jsondecode(azapi_resource.serverless_endpoint.output).properties.inferenceEndpoint.uri
}

output "foundry_workspace_id" {
  description = "Azure AI Foundry workspace resource ID"
  value       = azurerm_machine_learning_workspace.foundry.id
}

output "foundry_serverless_model" {
  description = "Azure AI Foundry serverless model ID"
  value       = var.serverless_model_id
}

output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.siyuan.name
}