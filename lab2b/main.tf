terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "rg" {
  name     = "az104-rg2"
  location = "East US"

  tags = {
    "Cost Center" = "000"
  }
}

data "azurerm_policy_definition" "inherit_tag" {
  display_name = "Inherit a tag from the resource group if missing"
}

resource "azurerm_resource_group_policy_assignment" "inherit_tag_assignment" {
  name                 = "inherit-cost-center-tag"
  display_name         = "Inherit the Cost Center tag and its value 000 from the resource group if missing"
  description          = "Inherit the Cost Center tag and its value 000 from the resource group if missing"
  resource_group_id    = azurerm_resource_group.rg.id
  policy_definition_id = data.azurerm_policy_definition.inherit_tag.id
  location             = azurerm_resource_group.rg.location

  identity {
    type = "SystemAssigned"
  }

  parameters = jsonencode({
    tagName = {
      value = "Cost Center"
    }
  })
}

resource "azurerm_role_assignment" "policy_tag_contributor" {
  scope                            = azurerm_resource_group.rg.id
  role_definition_name             = "Tag Contributor"
  principal_id                     = azurerm_resource_group_policy_assignment.inherit_tag_assignment.identity[0].principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

resource "azurerm_resource_group_policy_remediation" "remediate_tags" {
  name                 = "remediate-cost-center-tags"
  resource_group_id    = azurerm_resource_group.rg.id
  policy_assignment_id = azurerm_resource_group_policy_assignment.inherit_tag_assignment.id

  depends_on = [azurerm_role_assignment.policy_tag_contributor]
}

resource "random_string" "sa_suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "azurerm_storage_account" "test_sa" {
  name                     = "az104demo${random_string.sa_suffix.result}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  lifecycle {
    ignore_changes = [tags]
  }

  depends_on = [
    azurerm_resource_group_policy_assignment.inherit_tag_assignment,
    azurerm_role_assignment.policy_tag_contributor
  ]
}

resource "azurerm_management_lock" "rg_lock" {
  name       = "rg-lock"
  scope      = azurerm_resource_group.rg.id
  lock_level = "CanNotDelete"
  notes      = "Lab 02b Resource Lock - Prevent Deletion"

  depends_on = [
    azurerm_resource_group_policy_assignment.inherit_tag_assignment,
    azurerm_resource_group_policy_remediation.remediate_tags,
    azurerm_storage_account.test_sa
  ]
}

output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "storage_account_name" {
  value = azurerm_storage_account.test_sa.name
}
