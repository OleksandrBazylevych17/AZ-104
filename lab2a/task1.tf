terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
  }
}

provider "azurerm" {
  features {}
}

provider "azuread" {}

data "azurerm_subscription" "current" {}

resource "azurerm_management_group" "az104_mg1" {
  display_name = "az104-mg1"
  name         = "az104-mg1"

  subscription_ids = [
    data.azurerm_subscription.current.subscription_id,
  ]
}

output "management_group_id" {
  value = azurerm_management_group.az104_mg1.id
}
