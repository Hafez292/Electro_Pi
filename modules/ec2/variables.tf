variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID where EC2 will be launched"
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

variable "instance_name" {
  description = "Name of the EC2 instance"
  type        = string
}

variable "security_group_id" {
  description = "ID of the security group to attach to the instance"
  type        = string
}
variable "allowed_ssh_cidr" {
  description = "CIDR allowed to SSH"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_ip" {
  description = "Whether to enable public IP for the EC2 instance"
  type        = bool
  default     = false
}
variable "iam_instance_profile" {
  description = "Optional IAM instance profile to attach to the EC2"
  type        = string
  default     = null
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