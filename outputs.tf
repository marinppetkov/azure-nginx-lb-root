output "priavate_VM_internal_IP1" {
  description = "private VM private IP address"
  value       = azurerm_linux_virtual_machine.web-server.private_ip_addresses[0]
}
output "priavate_VM_internal_IP2" {
  description = "private VM private IP address"
  value       = azurerm_linux_virtual_machine.web-server.private_ip_addresses[1]
}
output "public_VM_address" {
  description = "VM public ip address"
  value       = azurerm_linux_virtual_machine.web-server.public_ip_address
}
output "lb_public_ip" {
  value = azurerm_public_ip.lb_public_ip.ip_address
}
