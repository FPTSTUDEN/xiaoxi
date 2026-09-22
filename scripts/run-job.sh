az containerapp job start \
  --name azure-xiaoxi-siyuan-setup \
  --resource-group rg-siyuan-prod

# check logs
az containerapp job logs \
  --name azure-xiaoxi-siyuan-setup \
  --resource-group rg-siyuan-prod \
  --follow