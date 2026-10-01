variable "instance_name" {
  description = "Name of the EC2 instance"
  type        = string
  
}
variable "instance_type" {
    description = "EC2 instance type"
    type        = string
    default     = "t2.micro"
}
variable "key_name" {
    description = "Existing key pair name"
    type        = string
}
variable "bastion_instance_type" {
    description = "EC2 instance type for the bastion host"
    type        = string
    default     = "t2.micro"
}
variable "add_tag" {
  description = "Private tag for EC2 instance"
  type        = map(string)
  default     = null
}
variable "root_volume_size" {
  description = "Size of the root EBS volume in GB"
  type        = number
  default     = 8
}
variable "volume_type" {
  description = "Type of the root EBS volume"
  type        = string
  default     = "gp3"
}