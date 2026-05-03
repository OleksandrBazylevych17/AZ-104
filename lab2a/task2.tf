resource "azuread_group" "helpdesk" {
  display_name     = "helpdesk"
  description      = "Helpdesk users for AZ-104 lab RBAC assignments"
  security_enabled = true
}

resource "azurerm_role_assignment" "helpdesk_vm_contributor" {
  scope                = azurerm_management_group.az104_mg1.id
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = azuread_group.helpdesk.object_id
}
