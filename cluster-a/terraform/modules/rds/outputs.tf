output "database_endpoint" {
  description = "RDS database endpoint"
  value       = aws_db_instance.main.endpoint
}

output "database_name" {
  description = "RDS database name"
  value       = aws_db_instance.main.db_name
}

output "database_port" {
  description = "RDS database port"
  value       = aws_db_instance.main.port
}

output "database_username" {
  description = "RDS database username"
  value       = aws_db_instance.main.username
}

output "database_identifier" {
  description = "RDS database identifier"
  value       = aws_db_instance.main.identifier
}

output "database_security_group_id" {
  description = "RDS database security group ID"
  value       = aws_security_group.rds.id
} 