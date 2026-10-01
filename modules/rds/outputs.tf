output "endpoint" {
  description = "The generated endpoint address needed by applications to establish connections"
  value       = aws_db_instance.db.endpoint
}

output "id" {
  description = "The AWS resource unique identifier assigned to the live RDS instance cluster"
  value       = aws_db_instance.db.id
}