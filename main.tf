terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "3.86.0"
    }
  }
}
provider "azurerm" {
  features {}
}
resource "azurerm_resource_group" "rg-nginx" {
  name     = "${var.prefix}-group"
  location = var.location
}
resource "azurerm_virtual_network" "nginx-vnet" {
  name                = "${var.prefix}-network"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg-nginx.location
  resource_group_name = azurerm_resource_group.rg-nginx.name
}
resource "azurerm_subnet" "internal" {
  name                 = "internal"
  resource_group_name  = azurerm_resource_group.rg-nginx.name
  virtual_network_name = azurerm_virtual_network.nginx-vnet.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_subnet" "public" {
  name                 = "public"
  resource_group_name  = azurerm_resource_group.rg-nginx.name
  virtual_network_name = azurerm_virtual_network.nginx-vnet.name
  address_prefixes     = ["10.0.3.0/24"]
}
### Internal interface
resource "azurerm_network_interface" "internal" {
  name                = "${var.prefix}-private-nic"
  resource_group_name = azurerm_resource_group.rg-nginx.name
  location            = azurerm_resource_group.rg-nginx.location

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.internal.id
    private_ip_address_allocation = "Dynamic"
  }
}
## Public interface
resource "azurerm_public_ip" "vm-publicIP" {
  name                = "${var.prefix}-pip"
  resource_group_name = azurerm_resource_group.rg-nginx.name
  location            = azurerm_resource_group.rg-nginx.location
  allocation_method   = "Static"
}
resource "azurerm_network_interface" "public" {
  name                = "${var.prefix}-public-nic"
  resource_group_name = azurerm_resource_group.rg-nginx.name
  location            = azurerm_resource_group.rg-nginx.location

  ip_configuration {
    name                          = "public"
    subnet_id                     = azurerm_subnet.public.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm-publicIP.id
  }
}

### Linux VM
resource "azurerm_linux_virtual_machine" "web-server" {
  name                            = "${var.prefix}-vm"
  admin_username                  = var.userName
  disable_password_authentication = false
  admin_password                  = var.userPassword
  user_data                       = base64encode(file("nginx.sh"))
  resource_group_name             = azurerm_resource_group.rg-nginx.name
  location                        = azurerm_resource_group.rg-nginx.location
  network_interface_ids           = [azurerm_network_interface.public.id, azurerm_network_interface.internal.id]
  size                            = "Standard_F2s_v2"
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
}

### Security group

resource "azurerm_network_security_group" "vm-sg-ssh" {
  name                = "vm-public-ssh-access"
  location            = azurerm_resource_group.rg-nginx.location
  resource_group_name = azurerm_resource_group.rg-nginx.name
}
resource "azurerm_network_interface_security_group_association" "public-ssh" {
  network_interface_id      = azurerm_network_interface.public.id
  network_security_group_id = azurerm_network_security_group.vm-sg-ssh.id
}

resource "azurerm_network_security_group" "vm-sg-http" {
  name                = "vm-internal-http-access"
  location            = azurerm_resource_group.rg-nginx.location
  resource_group_name = azurerm_resource_group.rg-nginx.name
}
resource "azurerm_network_interface_security_group_association" "private-http" {
  network_interface_id      = azurerm_network_interface.internal.id
  network_security_group_id = azurerm_network_security_group.vm-sg-http.id
}


resource "azurerm_network_security_rule" "vm-internal-http-access" {
  name                        = "httpAcces"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = 80
  source_address_prefix       = "*"
  destination_address_prefix  = azurerm_linux_virtual_machine.web-server.private_ip_addresses[1]
  resource_group_name         = azurerm_resource_group.rg-nginx.name
  network_security_group_name = azurerm_network_security_group.vm-sg-http.name
}

resource "azurerm_network_security_rule" "vm-public-ssh-access" {
  name                        = "sshAccess"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = 22
  source_address_prefix       = "*"
  destination_address_prefix  = azurerm_linux_virtual_machine.web-server.private_ip_addresses[0]
  resource_group_name         = azurerm_resource_group.rg-nginx.name
  network_security_group_name = azurerm_network_security_group.vm-sg-ssh.name
}

#### Load balancer
resource "azurerm_public_ip" "lb_public_ip" {
  name                = "${var.prefix}PublicIPForLB"
  location            = azurerm_resource_group.rg-nginx.location
  resource_group_name = azurerm_resource_group.rg-nginx.name
  allocation_method   = "Static"
}

resource "azurerm_lb" "nginx_lb" {
  name                = "${var.prefix}-LoadBalancer"
  location            = azurerm_resource_group.rg-nginx.location
  resource_group_name = azurerm_resource_group.rg-nginx.name

  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.lb_public_ip.id
  }
}

resource "azurerm_lb_backend_address_pool" "backend_pool" {
  loadbalancer_id = azurerm_lb.nginx_lb.id
  name            = "${var.prefix}-BackEndAddressPool"
}
resource "azurerm_network_interface_backend_address_pool_association" "nic_bckend_association" {
  backend_address_pool_id = azurerm_lb_backend_address_pool.backend_pool.id
  ip_configuration_name   = azurerm_network_interface.internal.ip_configuration[0].name
  network_interface_id    = azurerm_network_interface.internal.id
}

resource "azurerm_lb_rule" "lb_rules" {
  loadbalancer_id                = azurerm_lb.nginx_lb.id
  name                           = "LBRule"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = azurerm_lb.nginx_lb.frontend_ip_configuration[0].name
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.backend_pool.id]
}

