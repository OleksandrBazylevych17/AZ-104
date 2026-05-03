resource "azurerm_role_definition" "custom_support_request_contributor" {
  name        = "Custom Support Request Contributor"
  scope       = azurerm_management_group.az104_mg1.id
  description = "Can create and manage support requests, except support provider registration."

  permissions {
    actions = [
      "Microsoft.Support/*"
    ]
    not_actions = [
      "Microsoft.Support/register/action"
    ]
  }

  assignable_scopes = [
    azurerm_management_group.az104_mg1.id
  ]
}

resource "azurerm_role_assignment" "helpdesk_custom_support_request" {
  scope              = azurerm_management_group.az104_mg1.id
  role_definition_id = azurerm_role_definition.custom_support_request_contributor.role_definition_resource_id
  principal_id       = azuread_group.helpdesk.object_id
}
