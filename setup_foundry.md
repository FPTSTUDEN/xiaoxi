**1. Choose the model ID**

Your current default is:

```hcl
serverless_model_id = "DeepSeek-V3-0324"
```

Use the exact model ID shown in Azure AI Foundry for your region. Add it to `terraform.tfvars` if needed.

**2. Set the SiYuan password**

Update `terraform.tfvars`:

```hcl
siyuan_auth_code = "your-siyuan-password"
```

The endpoint URI and API key are fetched automatically by Terraform. The key is stored in Terraform state and passed to the Container App as a secret, so protect `terraform.tfstate` and do not commit it.

**3. Run the full plan**

```powershell
terraform plan -out=tfplan
```

Review it carefully. Your current state includes the old Azure OpenAI Cognitive Account, so the full plan will try to destroy it. It may also replace the Container Apps environment because of the workload profile change.

If the plan is acceptable:

```powershell
terraform apply tfplan
```

Finally, retrieve the SiYuan URL:

```powershell
terraform output -raw siyuan_url
```

The Foundry workspace, serverless endpoint, endpoint URI, and endpoint key are all Terraform-managed.