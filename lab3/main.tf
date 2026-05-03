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

resource "azurerm_resource_group" "lab_rg" {
  name     = "az104-rg3"
  location = "East US"
}

locals {
  lab_disks = {
    disk1 = {
      name = "az104-disk1"
      sku  = "Standard_LRS"
    }
    disk3 = {
      name = "az104-disk3"
      sku  = "Standard_LRS"
    }
    disk4 = {
      name = "az104-disk4"
      sku  = "Standard_LRS"
    }
    disk5 = {
      name = "az104-disk5"
      sku  = "StandardSSD_LRS"
    }
  }
}

resource "azurerm_managed_disk" "disks" {
  for_each             = local.lab_disks
  name                 = each.value.name
  location             = azurerm_resource_group.lab_rg.location
  resource_group_name  = azurerm_resource_group.lab_rg.name
  storage_account_type = each.value.sku
  create_option        = "Empty"
  disk_size_gb         = 32
}
