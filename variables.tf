variable "prefix" {
  description = "Prefix for azure resources"
  default     = "nginx"
}
variable "location" {
  description = "Azure region"
  default     = "westus2"
}

variable "userName" {
  description = "Admin user name"
}
variable "userPassword" {
  description = "Password for admin user"
}
