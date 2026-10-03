# Xiaoxi: SiYuan on Azure Container Apps

This Terraform project deploys a persistent [SiYuan](https://b3log.org/siyuan/en/) instance on Azure Container Apps and configures its AI provider with an Azure OpenAI deployment.

## What is deployed

`main.tf` creates the following resources in the configured resource group:

- An Azure StorageV2 account with a 10 GB Azure Files share for the SiYuan workspace.
- A virtual network and delegated subnet for the Container Apps environment.
- An Azure Container Apps environment backed by Log Analytics.
- A public SiYuan Container App listening on port `6806`, using `b3log/siyuan:v3.8.5`.
- An Azure OpenAI cognitive account and model deployment.
- A manually triggered Container Apps Job that runs `scripts/bootstrap.sh`.

The bootstrap job waits for SiYuan to become ready, reads the API token from the mounted workspace configuration, and calls SiYuan's AI settings API. The configuration uses the Azure OpenAI-compatible `/openai/v1` endpoint.

## Prerequisites

Install and authenticate the following tools:

- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)
- [Terraform](https://developer.hashicorp.com/terraform/install) `>= 1.5.0`

The Azure subscription must allow creation of Container Apps, Azure Files, Log Analytics, Application Insights, and Azure OpenAI resources. The selected Azure OpenAI model, version, deployment SKU, and capacity must also be available in the selected region and subscription.

Sign in and select the target subscription:

```bash
az login
az account set --subscription "<subscription-id-or-name>"
```

## Configuration

Create a private variable file from the example:

```bash
cp terraform.tfvars.example terraform.tfvars
```

On Windows PowerShell, use:

```powershell
Copy-Item terraform.tfvars.example terraform.tfvars
```

At minimum, set these values in `terraform.tfvars`:

```hcl
resource_group_name  = "rg-siyuan-prod"
location             = "swedencentral"
project_name         = "azure-xiaoxi-siyuan"
storage_account_name = "stsiyuanprod001" # globally unique, lowercase, 3-24 characters
siyuan_auth_code     = "<strong-secret>"
timezone             = "Europe/Stockholm"
```

The Azure OpenAI defaults are defined in `variables.tf`. Override `openai_model_name`, `openai_model_version`, `openai_deployment_name`, and `openai_capacity` when using another model or deployment. Verify the exact values with Azure before applying.

## Deploy

From the repository root:

```bash
terraform init
terraform fmt -check
terraform validate
terraform plan -var-file="terraform.tfvars"
terraform apply -var-file="terraform.tfvars"
```

Terraform creates the Container App before the bootstrap job, but the bootstrap job is manual and does not run automatically as part of `terraform apply`.

After applying, display the important outputs:

```bash
terraform output siyuan_url
terraform output azure_openai_endpoint
terraform output azure_openai_deployment
```

Open the value of `siyuan_url` in a browser. Use the `siyuan_auth_code` as the SiYuan access code when prompted.

## Run the AI bootstrap job

The helper script starts the deployed job and follows its logs:

```bash
sh scripts/run-job.sh
```

The script currently targets:

```text
Job:            azure-xiaoxi-siyuan-setup
Resource group: rg-siyuan-prod
```

These values come from the example `project_name` and `resource_group_name`. If either Terraform variable is changed, update `scripts/run-job.sh` accordingly, or run the equivalent commands directly:

```bash
az containerapp job start \
  --name "<project-name>-setup" \
  --resource-group "<resource-group-name>"

az containerapp job logs \
  --name "<project-name>-setup" \
  --resource-group "<resource-group-name>" \
  --follow
```

The job can be run again after changing the AI settings. It has one replica, a 10-minute timeout, and up to three retries.

## Troubleshooting

### The bootstrap job cannot reach SiYuan

Confirm that the Container App is running and inspect its logs:

```bash
az containerapp revision list \
  --name "<project-name>-app" \
  --resource-group "<resource-group-name>" \
  --output table

az containerapp logs show \
  --name "<project-name>-app" \
  --resource-group "<resource-group-name>" \
  --follow
```

The bootstrap script checks `/api/system/version` up to 30 times, waiting 10 seconds between attempts.

### `conf.json` or `api.token` is missing

SiYuan must complete its first startup and initialize the persistent workspace before the job can read the token. Check that the Azure Files share is mounted and that the workspace contains `conf/conf.json`. The job mounts the `conf` subpath read-only at `/siyuan-conf`.

### The Azure OpenAI deployment fails

Model availability varies by region, subscription, version, SKU, and quota. Check the model and deployment options in the Azure portal or Azure CLI, then update the OpenAI variables and run `terraform plan` again.

## Security and operational notes

- Do not commit `terraform.tfvars`; it contains the SiYuan access code. The repository's `.gitignore` excludes it.
- Terraform state can contain sensitive values, including resource secrets. Keep `terraform.tfstate` in protected storage and do not publish it.
- The SiYuan app ingress is externally enabled. Restrict access with Azure networking or an upstream access layer if the instance should not be public.
- The storage account and Azure Files share are created with standard LRS storage. Adjust the Terraform configuration if higher durability or a different access tier is required.

## Destroy the deployment

To remove all resources managed by this configuration:

```bash
terraform destroy -var-file="terraform.tfvars"
```

This deletes the storage account and its workspace data as well, so export or back up the SiYuan workspace first.