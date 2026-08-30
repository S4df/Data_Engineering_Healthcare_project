# Data Engineering Healthcare Project

Terraform infrastructure for a healthcare data engineering lab on Azure, using
a `clnt` (Clinicient) naming convention throughout.

## Layout

| Folder | What it builds |
| --- | --- |
| `azure-sql/` | Resource group `clnt-rg`, one logical SQL Server, and the `clntdba` / `clntdbb` databases |
| `azure-adls/` | ADLS Gen2 storage account with medallion-architecture containers |

Each folder is an independent Terraform root module with its own state. They are
applied separately, not as one configuration.

## Apply order

`azure-sql` must be applied first. It creates the `clnt-rg` resource group, which
`azure-adls` then looks up read-only via a `data "azurerm_resource_group"` block
rather than creating its own.

```bash
cd azure-sql
terraform init
terraform apply

cd ../azure-adls
terraform init
terraform apply
```

## Required variables

`azure-sql` needs two inputs, supplied via `terraform.tfvars` (gitignored):

- `sql_admin_password` — admin password for the SQL Server
- `my_ip` — your public IP for the server firewall rule, from `curl -4 ifconfig.me`

## Containers

`azure-adls` provisions `landing`, `bronze`, `silver`, `gold`, and `configs`,
all private.
