module "my_mssql_database" {
  source = "../../../modules/rds"

  identifier            = "electro-db"
  instance_class        = "db.t3.medium"
  allocated_storage     = 20
  max_allocated_storage = 100 # Auto-scales incrementally up to 200GB under storage stress

  # Networking dependencies (Pass private subnet IDs to preserve zero-public exposure policy)
  subnet_ids         = data.terraform_remote_state.vpc.outputs.private_subnet_ids
  security_group_ids = data.terraform_remote_state.permission.outputs.sg_rds != null ? [data.terraform_remote_state.permission.outputs.sg_rds] : [] # Attach RDS SG if defined, else empty list

  # Master Administrative Credentials
  db_username = var.db_username
  db_password = var.db_password

  # Existing IAM profile configuration mapping
  existing_iam_role_arn = data.terraform_remote_state.permission.outputs.rds_access_role_S3 != null ? data.terraform_remote_state.permission.outputs.rds_access_role_S3 : "" # Attach S3 access role if defined, else empty string
  iam_feature_name      = "S3_INTEGRATION" # Standard value for MS SQL native S3 operations

  environment = "electro"
}

