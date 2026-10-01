variable "cidr_vpc" {
  description = "The CIDR block for the VPC"
  type        = string
}
variable "tag" {
    description = "The tag for the VPC"
    type        = string
  
}
variable "cidr_Public_Subnets" {
    description = "A map of CIDR blocks for public subnets, with subnet names as keys"
    type = map(string) 
}   
variable "cidr_Private_Subnets" {
    description = "A map of CIDR blocks for private subnets, with subnet names as keys"
    type = map(string)
}
variable "azs" {
  description = "List of AZs for subnets"
  type        = list(string)
}

variable "enable_dns_hostnames" {
  description = "Enable DNS hostnames in the VPC"
  type        = bool
  default     = null
  
}