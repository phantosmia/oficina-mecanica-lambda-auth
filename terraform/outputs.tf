output "api_endpoint" {
  description = "URL base do API Gateway HTTP API."
  value       = aws_apigatewayv2_api.main.api_endpoint
}

output "auth_endpoint" {
  description = "URL completa da rota de autenticacao via CPF (POST)."
  value       = "${aws_apigatewayv2_api.main.api_endpoint}/auth/cpf"
}

output "authenticate_function_name" {
  description = "Nome da funcao Lambda de autenticacao (valida CPF, consulta o RDS e emite o JWT)."
  value       = aws_lambda_function.authenticate.function_name
}

output "authenticate_function_arn" {
  description = "ARN da funcao Lambda de autenticacao."
  value       = aws_lambda_function.authenticate.arn
}

output "authorizer_function_name" {
  description = "Nome da funcao Lambda usada como Lambda Authorizer."
  value       = aws_lambda_function.authorizer.function_name
}

output "authorizer_id" {
  description = "ID do Lambda Authorizer no API Gateway, para anexar a futuras rotas protegidas."
  value       = aws_apigatewayv2_authorizer.jwt_client.id
}

output "lambda_role_arn" {
  description = "ARN da IAM role usada pelas duas funcoes Lambda (propria ou fornecida via lambda_execution_role_arn)."
  value       = local.lambda_role_arn
}
