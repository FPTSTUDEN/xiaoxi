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

## Gotchas

This section records the issues that have already caused deployment or bootstrap failures. Check it before changing the container command, volume mounts, or AI payload.

### 1. Do not replace the SiYuan image entrypoint with `command = ["serve"]`

The `b3log/siyuan:v3.8.5` image entrypoint invokes the SiYuan kernel. The Terraform configuration therefore passes the kernel arguments with:

```hcl
args = ["serve", "--workspace=/siyuan/workspace/"]
```

Do not add a separate `command` unless you have verified the entrypoint behavior of the new image. Replacing the entrypoint can cause the container to start incorrectly or not start at all.

### 2. Pass the access code through the environment, not the command line

SiYuan receives the access code through the `SIYUAN_ACCESS_AUTH_CODE` secret environment variable. It is intentionally not included in the container arguments. Command-line handling changed with the SiYuan image version and can expose the secret in deployment metadata or process listings.

### 3. The bootstrap job needs the `conf` subpath, not the whole workspace

The job mounts the Azure Files environment storage at `/siyuan-conf` with `sub_path = "conf"`, so the expected file is:

```text
/siyuan-conf/conf.json
```

The mount is read-only on purpose. Mounting the entire workspace, using the wrong subpath, or running the job before SiYuan's first boot has created `conf/conf.json` results in `conf.json not found` or a missing `api.token`. Wait for the app to initialize once before starting the job.

### 4. Read the API token from `api.token`; do not log in with the auth code

The current bootstrap flow extracts `.api.token` from `conf.json` and sends it as:

```text
Authorization: Token <api-token>
```

The older login-and-cookie approach is not the current implementation. If the token is empty, the workspace was probably not initialized, the mount path is wrong, or the SiYuan image changed its configuration schema.

### 5. The job script is injected through `$0`, so keep the `printf` wrapper

The job uses Alpine's `/bin/sh -c`, installs dependencies, and then receives the Terraform `file(...)` content as the command's `$0` argument. This is why the command is:

```text
apk add --no-cache curl ca-certificates && printf '%s\n' "$0" | /bin/sh -s
```

Changing this back to `exec /bin/sh -s` does not pipe the script content into the shell and causes confusing bootstrap startup failures.

### 6. Azure Files requires the network and mount options in this configuration

The Container Apps environment uses the delegated `Microsoft.App/environments` subnet because Azure Files is mounted through the environment. The `nobrl` and `serverino` options on the SiYuan workspace mount are also deliberate; removing them can produce file-locking or inode-related errors. Keep the workspace mount writable and the bootstrap `conf` mount read-only.

### 7. The SiYuan AI payload must match the installed SiYuan version

The bootstrap script uses the current provider shape: a top-level `providers` array with `apiKey`, `baseURL`, `protocol`, and nested `models`. It is not the older `Provider`/`OpenAI` or `APIKey`/`APIModel` shape. The current endpoint is `${AZURE_OPENAI_ENDPOINT}/openai/v1` (with a trailing slash safely removed before appending the path).

If a request reports success but the response contains zero providers, the script fails deliberately instead of reporting a false positive. If SiYuan is upgraded, verify its settings API schema before updating this payload.

### 8. A successful HTTP/API response is not enough

The bootstrap job checks that SiYuan returns `"code":0`, verifies that at least one provider was returned, and removes provider API keys before logging the response. Inspect the job logs for the sanitized response when diagnosing an AI configuration issue; never add the raw response or API key to logs.

### 9. Pin and test the SiYuan image before upgrading

The deployment pins `b3log/siyuan:v3.8.5` rather than using a floating tag. Container entrypoints, auth behavior, configuration paths, and AI settings schemas are image-version-sensitive. Upgrade the image only after checking all of those assumptions and testing the bootstrap job against the new version.

### 10. Container Apps jobs are manual, and the helper names are not dynamic

`terraform apply` creates the bootstrap job but does not run it. Also, `scripts/run-job.sh` currently hard-codes `azure-xiaoxi-siyuan-setup` and `rg-siyuan-prod`. If `project_name` or `resource_group_name` changes, update the helper or use the equivalent Azure CLI commands with the generated names.

### 11. `Consumption` must match the environment workload profile

Both the app and job explicitly use the `Consumption` workload profile created by the environment. Removing `workload_profile_name = "Consumption"` or selecting a profile that does not exist in the environment can prevent deployment or revision creation.

### 12. Azure OpenAI model values are region- and quota-dependent

The model name, version, deployment name, capacity, and `GlobalStandard` SKU are not universally valid. A Terraform configuration can validate while Azure rejects the deployment. Confirm availability and quota in the target region and subscription before applying, especially when copying values from `terraform.tfvars.example` or `models.txt`.

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