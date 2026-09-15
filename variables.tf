variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-siyuan-prod"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "swedencentral"
}

variable "project_name" {
  description = "Project name prefix"
  type        = string
  default     = "siyuan"
}

variable "storage_account_name" {
  description = "Globally unique storage account name (lowercase, 3-24 chars, alphanumeric only)"
  type        = string
}

variable "siyuan_auth_code" {
  description = "SiYuan lock screen password"
  type        = string
  sensitive   = true
}

variable "timezone" {
  description = "Timezone for the container"
  type        = string
  default     = "UTC"
}

variable "container_cpu" {
  description = "CPU for the container"
  type        = number
  default     = 0.5
}

variable "container_memory" {
  description = "Memory for the container"
  type        = string
  default     = "1Gi"
}

variable "min_replicas" {
  description = "Minimum replicas (0 = scale to zero, 1 = always warm)"
  type        = number
  default     = 1
}

variable "max_replicas" {
  description = "Maximum replicas (SiYuan is single-user, keep at 1)"
  type        = number
  default     = 1
}

# Azure OpenAI variables
variable "openai_deployment_name" {
  description = "Name of the model deployment"
  type        = string
  default     = "gpt-4o-mini"
}

variable "openai_model_name" {
  description = "OpenAI model name"
  type        = string
  default     = "gpt-4o-mini"
}

variable "openai_model_version" {
  description = "OpenAI model version"
  type        = string
  default     = "2024-07-18"
}

variable "openai_capacity" {
  description = "OpenAI deployment capacity (thousands of tokens per minute)"
  type        = number
  default     = 10
}

variable "tags" {
  description = "Tags for all resources"
  type        = map(string)
  default = {
    Environment = "production"
    Project     = "xiaoxi"
    ManagedBy   = "terraform"
  }
}