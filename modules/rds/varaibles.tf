variable "identifier" {
  description = "The unique name identifier for the RDS instance"
  type        = string
}

variable "instance_class" {
  description = "The compute instance capacity type for the RDS instance (e.g., db.t3.small)"
  type        = string
  default     = "db.t3.small"
}

variable "allocated_storage" {
  description = "The initial size of the database storage in gigabytes (GB)"
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "The peak ceiling capacity for RDS storage auto-scaling. Set higher than allocated_storage to enable auto-scaling."
  type        = number
  default     = 100
}

variable "subnet_ids" {
  description = "A distinct list of VPC subnet IDs used to create the DB subnet group"
  type        = list(string)
}

variable "security_group_ids" {
  description = "A list of VPC security groups mapped directly to the database network boundary"
  type        = list(string)
}

variable "db_username" {
  description = "Master administrative username for SQL server login operations"
  type        = string
  sensitive   = true 
}

variable "db_password" {
  type        = string
  description = "The master password for the MS SQL database."
  sensitive   = true 
}


variable "environment" {
  description = "Deployment lifestyle classification context tag"
  type        = string
  default     = "dev"
}