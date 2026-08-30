# ================================================================
# ADLS GEN2 STORAGE ACCOUNT - CLNT Data Engineering Project
# ================================================================
# Standalone project - references the EXISTING clnt-rg resource
# group (created by the azure-sql project) via a data source,
# rather than creating a new one. This keeps everything under one
# logical resource group in Azure even though the Terraform code
# lives in a separate folder/state.
# ================================================================

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Look up the existing resource group by name - read-only,
# doesn't create or manage it, just references it.
data "azurerm_resource_group" "clnt" {
  name = "clnt-rg"
}

# ================================================================
# STORAGE ACCOUNT - is_hns_enabled = true is what makes this
# ADLS Gen2 instead of plain flat blob storage.
# ================================================================
resource "azurerm_storage_account" "clnt_adls" {
  name                     = "clntadlsdev"
  resource_group_name      = data.azurerm_resource_group.clnt.name
  location                 = data.azurerm_resource_group.clnt.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  is_hns_enabled           = true

  tags = {
    Project = "clnt-data-engineering"
  }
}

# ================================================================
# CONTAINERS - medallion architecture layout
# ================================================================
resource "azurerm_storage_container" "landing" {
  name                  = "landing"
  storage_account_name  = azurerm_storage_account.clnt_adls.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "bronze" {
  name                  = "bronze"
  storage_account_name  = azurerm_storage_account.clnt_adls.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "silver" {
  name                  = "silver"
  storage_account_name  = azurerm_storage_account.clnt_adls.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "gold" {
  name                  = "gold"
  storage_account_name  = azurerm_storage_account.clnt_adls.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "configs" {
  name                  = "configs"
  storage_account_name  = azurerm_storage_account.clnt_adls.name
  container_access_type = "private"
}

# ================================================================
# OUTPUTS
# ================================================================
output "adls_storage_account_name" {
  value = azurerm_storage_account.clnt_adls.name
}

output "adls_primary_dfs_endpoint" {
  description = "The Data Lake (dfs) endpoint - use in Databricks/Spark configs"
  value       = azurerm_storage_account.clnt_adls.primary_dfs_endpoint
}