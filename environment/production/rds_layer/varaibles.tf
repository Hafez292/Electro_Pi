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