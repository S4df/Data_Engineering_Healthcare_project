# ================================================================
# AZURE SQL DATABASE - Clinicient (CLNT) Data Engineering Project
# ================================================================
# Naming convention: "clnt" prefix throughout, echoing the real
# project context (Clinicient) - two databases created on one
# logical SQL Server, mirroring a common real-world pattern where
# one server hosts multiple tenant/environment databases.
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

# ================================================================
# RESOURCE GROUP - the container everything else lives inside
# ================================================================
resource "azurerm_resource_group" "clnt" {
  name     = "clnt-rg"
  location = "Central India"
}

# ================================================================
# AZURE SQL SERVER - logical server / connection endpoint
# ================================================================
# Reminder: this is NOT a VM. It's the management endpoint that
# both databases below connect through - one server, two databases,
# same pattern as hosting multiple tenant DBs on one SQL Server
# instance in your real AG fleet.
resource "azurerm_mssql_server" "clnt" {
  name                         = "clnt-sqlserver-shahed"  # must be globally unique across ALL of Azure
  resource_group_name          = azurerm_resource_group.clnt.name
  location                     = azurerm_resource_group.clnt.location
  version                      = "12.0"
  administrator_login          = "clntadmin"
  administrator_login_password = var.sql_admin_password
}

variable "sql_admin_password" {
  description = "Admin password for the CLNT Azure SQL Server"
  type        = string
  sensitive   = true
}

# ================================================================
# DATABASE A - clntdba
# ================================================================
resource "azurerm_mssql_database" "clntdba" {
  name      = "clntdba"
  server_id = azurerm_mssql_server.clnt.id
  sku_name  = "Basic"

  tags = {
    Project = "clnt-data-engineering"
    Env     = "dba"
  }
}

# ================================================================
# DATABASE B - clntdbb
# ================================================================
resource "azurerm_mssql_database" "clntdbb" {
  name      = "clntdbb"
  server_id = azurerm_mssql_server.clnt.id
  sku_name  = "Basic"

  tags = {
    Project = "clnt-data-engineering"
    Env     = "dbb"
  }
}

# ================================================================
# FIREWALL RULE - allow your IP to reach the server
# ================================================================
# Applies at the SERVER level, so it covers both clntdba and
# clntdbb - unlike AWS security groups, no VPC/subnet ceremony
# needed here to get a working connection.
resource "azurerm_mssql_firewall_rule" "my_ip" {
  name             = "allow-my-ip"
  server_id        = azurerm_mssql_server.clnt.id
  start_ip_address = var.my_ip
  end_ip_address   = var.my_ip
}

variable "my_ip" {
  description = "Your current public IP - get with: curl -4 ifconfig.me"
  type        = string
}

# ================================================================
# OUTPUTS
# ================================================================
output "sql_server_fqdn" {
  description = "Connect to this hostname in Azure Data Studio, port 1433"
  value       = azurerm_mssql_server.clnt.fully_qualified_domain_name
}

output "database_a_name" {
  value = azurerm_mssql_database.clntdba.name
}

output "database_b_name" {
  value = azurerm_mssql_database.clntdbb.name
}
