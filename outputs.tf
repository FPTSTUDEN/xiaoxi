output "siyuan_url" {
  description = "Public URL of the SiYuan app"
  value       = "https://${azurerm_container_app.siyuan.ingress[0].fqdn}"
}

output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.siyuan.name
}

output "azure_openai_endpoint" {
  description = "Azure OpenAI endpoint URL (use this in SiYuan AI settings)"
  value       = azurerm_cognitive_account.openai.endpoint
}

output "azure_openai_deployment" {
  description = "Azure OpenAI deployment name (use this as the Model in SiYuan AI settings)"
  value       = azurerm_cognitive_deployment.model.name
}

output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.siyuan.name
}