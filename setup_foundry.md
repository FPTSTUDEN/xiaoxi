**1. Choose the model ID**

Your current default is:

```hcl
serverless_model_id = "DeepSeek-V3-0324"
```

Use the exact model ID shown in Azure AI Foundry for your region. Add it to `terraform.tfvars` if needed.

**2. Create the Foundry resources first**

From the project directory:

```powershell
terraform apply "-target=azurerm_machine_learning_workspace.foundry" "-target=azapi_resource.serverless_endpoint"
```

Terraform will also create the required Key Vault, Application Insights, and storage dependencies.

**3. Retrieve the endpoint details**

After creation, open Azure AI Foundry:

1. Go to **Build** or **Model catalog**.
2. Open the deployed serverless endpoint.
3. Copy its **Inference URI**.
4. Copy or regenerate its **API key**.

Then update `terraform.tfvars`:

```hcl
serverless_endpoint_uri = "https://..."
serverless_endpoint_key = "your-key"
siyuan_auth_code         = "your-siyuan-password"
```

Do not commit the key to Git. Prefer setting it temporarily through an environment variable:

```powershell
$env:TF_VAR_serverless_endpoint_key = "your-key"
```

**4. Run the full plan**

```powershell
terraform plan -out=tfplan
```

Review it carefully. Your current state includes the old Azure OpenAI Cognitive Account, so the full plan will try to destroy it. It also currently plans to replace the Container Apps environment because of the workload profile change.

If the plan is acceptable:

```powershell
terraform apply tfplan
```

Finally, retrieve the SiYuan URL:

```powershell
terraform output -raw siyuan_url
```

The endpoint itself is Terraform-managed; only the endpoint URI/key retrieval is currently manual in this configuration.