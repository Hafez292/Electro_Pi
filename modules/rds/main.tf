# 1. Private Network isolation cluster allocation group
resource "aws_db_subnet_group" "rds" {
  name        = "${var.identifier}-subnet-group"
  subnet_ids  = var.subnet_ids
  description = "Isolated private database subnet mapping group for ${var.identifier}"

  tags = {
    Name        = "${var.identifier}-subnet-group"
    Environment = var.environment
  }
}

# 2. Main Amazon RDS Engine
resource "aws_db_instance" "db" {
  identifier           = var.identifier
  engine               = "postgres"     
  engine_version       = "16.3"   
  instance_class       = var.instance_class
  
  # Credentials & Storage parameters
  username               = var.db_username
  password               = var.db_password
  allocated_storage      = var.allocated_storage
  max_allocated_storage  = var.max_allocated_storage # Actively triggers AWS Storage Auto-Scaling mechanics
  storage_type           = "gp3"                     # Cost-efficient general-purpose base configuration

  # Network & Access Restrictions (Guarantees zero public fees & blocks brute-force vectors)
  db_subnet_group_name   = aws_db_subnet_group.rds.name
  vpc_security_group_ids = var.security_group_ids
  publicly_accessible    = false

  # =========================================================================
  # ABSOLUTE FREE-TIER DATABASE INSIGHTS & TELEMETRY ZERO-CHARGE LOCKS
  # =========================================================================
  performance_insights_enabled          = true # Standard Performance/Database Insights enabled
  performance_insights_retention_period = 7    # 7 Days is strictly the top-end ceiling of AWS Free-tier Insights

  # Disables secondary CloudWatch log streaming tasks to maintain zero monitoring costs
  monitoring_interval                   = 0    
  monitoring_role_arn                   = null 

  # Standard operational requirements 
  license_model        = "general-public-license"
  skip_final_snapshot  = true
  multi_az = false 

  tags = {
    Name        = var.identifier
    Environment = var.environment
  }
}
