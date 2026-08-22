output "role_arn" {
  description = "ARN da IAM role que o New Relic assume para ler métricas do RDS/API Gateway (própria ou reaproveitada via newrelic_integrations_role_arn)."
  value       = local.newrelic_role_arn
}

output "linked_account_id" {
  description = "ID da conta AWS vinculada dentro do New Relic (newrelic_cloud_aws_link_account)."
  value       = newrelic_cloud_aws_link_account.this.id
}
