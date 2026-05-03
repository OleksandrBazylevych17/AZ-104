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

locals {
  location = "East US 2"

  web_subnets = {
    "0" = {
      name   = "Subnet0"
      prefix = "10.60.0.0/24"
    }
    "1" = {
      name   = "Subnet1"
      prefix = "10.60.1.0/24"
    }
  }
}

resource "azurerm_resource_group" "rg" {
  name     = "az104-rg6"
  location = local.location
}

resource "random_password" "localadmin" {
  length           = 20
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "azurerm_virtual_network" "main" {
  name                = "az104-06-vnet1"
  address_space       = ["10.60.0.0/22"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "web" {
  for_each             = local.web_subnets
  name                 = each.value.name
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [each.value.prefix]
}

resource "azurerm_subnet" "appgw" {
  name                 = "subnet-appgw"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.60.3.224/27"]
}

resource "azurerm_network_security_group" "web" {
  name                = "az104-06-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "allow-http"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "web" {
  for_each                  = local.web_subnets
  subnet_id                 = azurerm_subnet.web[each.key].id
  network_security_group_id = azurerm_network_security_group.web.id
}

resource "azurerm_network_interface" "vm" {
  for_each            = local.web_subnets
  name                = "az104-06-nic${each.key}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.web[each.key].id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_windows_virtual_machine" "web" {
  for_each            = local.web_subnets
  name                = "az104-06-vm${each.key}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = "Standard_D2s_v3"
  admin_username      = "localadmin"
  admin_password      = random_password.localadmin.result
  network_interface_ids = [
    azurerm_network_interface.vm[each.key].id
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-Datacenter"
    version   = "latest"
  }

  boot_diagnostics {}
}

resource "azurerm_virtual_machine_extension" "iis" {
  for_each             = local.web_subnets
  name                 = "IIS-Setup"
  virtual_machine_id   = azurerm_windows_virtual_machine.web[each.key].id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  settings = jsonencode({
    commandToExecute = "powershell.exe -ExecutionPolicy Unrestricted -Command \"Install-WindowsFeature -Name Web-Server -IncludeManagementTools; Set-Content -Path 'C:\\inetpub\\wwwroot\\iisstart.htm' -Value ('Hello World from ' + $env:COMPUTERNAME); New-Item -Path 'C:\\inetpub\\wwwroot\\image' -ItemType Directory -Force; Set-Content -Path 'C:\\inetpub\\wwwroot\\image\\iisstart.htm' -Value ('Image from: ' + $env:COMPUTERNAME); New-Item -Path 'C:\\inetpub\\wwwroot\\video' -ItemType Directory -Force; Set-Content -Path 'C:\\inetpub\\wwwroot\\video\\iisstart.htm' -Value ('Video from: ' + $env:COMPUTERNAME)\""
  })
}

resource "azurerm_public_ip" "lb" {
  name                = "az104-lbpip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_lb" "public" {
  name                = "az104-lb"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "az104-fe"
    public_ip_address_id = azurerm_public_ip.lb.id
  }
}

resource "azurerm_lb_backend_address_pool" "web" {
  loadbalancer_id = azurerm_lb.public.id
  name            = "az104-be"
}

resource "azurerm_network_interface_backend_address_pool_association" "lb" {
  for_each                = local.web_subnets
  network_interface_id    = azurerm_network_interface.vm[each.key].id
  ip_configuration_name   = "internal"
  backend_address_pool_id = azurerm_lb_backend_address_pool.web.id
}

resource "azurerm_lb_probe" "http" {
  loadbalancer_id     = azurerm_lb.public.id
  name                = "az104-hp"
  port                = 80
  protocol            = "Tcp"
  interval_in_seconds = 5
}

resource "azurerm_lb_rule" "http" {
  loadbalancer_id                = azurerm_lb.public.id
  name                           = "az104-lbrule"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "az104-fe"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.web.id]
  probe_id                       = azurerm_lb_probe.http.id
  idle_timeout_in_minutes        = 4
}

resource "azurerm_public_ip" "appgw" {
  name                = "az104-gwpip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_application_gateway" "appgw" {
  name                = "az104-appgw"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  ssl_policy {
    policy_type = "Predefined"
    policy_name = "AppGwSslPolicy20220101"
  }

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 2
  }

  gateway_ip_configuration {
    name      = "az104-gwipconfig"
    subnet_id = azurerm_subnet.appgw.id
  }

  frontend_port {
    name = "az104-feport"
    port = 80
  }

  frontend_ip_configuration {
    name                 = "az104-gwfe"
    public_ip_address_id = azurerm_public_ip.appgw.id
  }

  backend_address_pool {
    name         = "az104-appgwbe"
    ip_addresses = [azurerm_network_interface.vm["0"].private_ip_address, azurerm_network_interface.vm["1"].private_ip_address]
  }

  backend_address_pool {
    name         = "az104-imagebe"
    ip_addresses = [azurerm_network_interface.vm["0"].private_ip_address]
  }

  backend_address_pool {
    name         = "az104-videobe"
    ip_addresses = [azurerm_network_interface.vm["1"].private_ip_address]
  }

  backend_http_settings {
    name                  = "az104-http"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
  }

  http_listener {
    name                           = "az104-listener"
    frontend_ip_configuration_name = "az104-gwfe"
    frontend_port_name             = "az104-feport"
    protocol                       = "Http"
  }

  request_routing_rule {
    name               = "az104-gwrule"
    rule_type          = "PathBasedRouting"
    http_listener_name = "az104-listener"
    url_path_map_name  = "az104-pathmap"
    priority           = 10
  }

  url_path_map {
    name                               = "az104-pathmap"
    default_backend_address_pool_name  = "az104-appgwbe"
    default_backend_http_settings_name = "az104-http"

    path_rule {
      name                       = "images"
      paths                      = ["/image/*"]
      backend_address_pool_name  = "az104-imagebe"
      backend_http_settings_name = "az104-http"
    }

    path_rule {
      name                       = "videos"
      paths                      = ["/video/*"]
      backend_address_pool_name  = "az104-videobe"
      backend_http_settings_name = "az104-http"
    }
  }
}

output "admin_username" {
  value = "localadmin"
}

output "admin_password" {
  value     = random_password.localadmin.result
  sensitive = true
}

output "load_balancer_public_ip" {
  value = azurerm_public_ip.lb.ip_address
}

output "application_gateway_public_ip" {
  value = azurerm_public_ip.appgw.ip_address
}
