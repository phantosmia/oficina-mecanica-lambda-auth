variable "project_name" {
  description = "Nome lógico do projeto para tags e nomes de recursos."
  type        = string
  default     = "oficina-mecanica-fiap"
}

variable "environment" {
  description = "Identificador do ambiente AWS."
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "Região AWS onde os recursos serão provisionados."
  type        = string
  default     = "us-east-1"
}

variable "tf_state_bucket" {
  description = "Bucket S3 do backend remoto do Terraform (o mesmo criado por infra/backend no repositório oficina-mecanica-fiap), usado para ler via terraform_remote_state os outputs dos repositórios oficina-mecanica-infra-banco-dados e oficina-mecanica-fiap."
  type        = string
  default     = "oficina-mecanica-fiap-terraform-state"
}

variable "tf_state_region" {
  description = "Região do backend S3 do state remoto."
  type        = string
  default     = "us-east-1"
}

variable "database_state_key" {
  description = "Key do state do repositório oficina-mecanica-infra-banco-dados no backend S3 compartilhado. Ajuste para o ambiente real (ex.: database/homologacao/terraform.tfstate) ao aplicar em homologacao/producao."
  type        = string
  default     = "database/dev/terraform.tfstate"
}

variable "app_state_key" {
  description = "Key do state de infra/aws do repositório oficina-mecanica-fiap no backend S3 compartilhado, de onde é lido o secret com o JWT_SECRET_KEY (app_secret_arn). Ajuste para o ambiente real (ex.: aws/homologacao/terraform.tfstate) ao aplicar em homologacao/producao."
  type        = string
  default     = "aws/dev/terraform.tfstate"
}

variable "kubernetes_state_key" {
  description = "Key do state do repositório oficina-mecanica-infra-kubernetes no backend S3 compartilhado, de onde são lidos vpc_id e private_subnet_ids para o VPC Link do proxy ao EKS (ADR-0006). Ajuste para o ambiente real (ex.: kubernetes/homologacao/terraform.tfstate) ao aplicar em homologacao/producao."
  type        = string
  default     = "kubernetes/dev/terraform.tfstate"
}

variable "lambda_execution_role_arn" {
  description = "ARN de uma IAM role existente para a execução das duas Lambdas (autenticação e authorizer). Vazio (padrão) cria uma role própria com as permissões mínimas (logs + acesso a ENI de VPC). Preencha em labs que bloqueiam iam:CreateRole (ex.: AWS Academy, reaproveitando a LabRole)."
  type        = string
  default     = ""
}

variable "jwt_algorithm" {
  description = "Algoritmo de assinatura do JWT. Deve ser o mesmo configurado em JWT_ALGORITHM na aplicação principal (padrão HS256)."
  type        = string
  default     = "HS256"
}

variable "access_token_expire_minutes" {
  description = "Validade, em minutos, do JWT emitido para o cliente."
  type        = number
  default     = 30
}

variable "lambda_memory_size" {
  description = "Memória (MB) alocada para as funções Lambda."
  type        = number
  default     = 256
}

variable "lambda_timeout" {
  description = "Timeout (segundos) das funções Lambda."
  type        = number
  default     = 10
}

variable "log_retention_days" {
  description = "Retenção dos CloudWatch Log Groups das funções, em dias."
  type        = number
  default     = 14
}

variable "eks_alb_listener_arn" {
  description = "ARN do listener HTTP:80 do ALB (interno) do Ingress da aplicação principal no EKS (k8s/overlays/aws/ingress.yaml do oficina-mecanica-fiap, ADR-0006). Vazio (padrão) não cria o VPC Link nem as rotas proxy — preencha depois que o Ingress existir (ver comentário em main.tf, recurso aws_apigatewayv2_integration.eks_proxy, para o passo a passo de obtenção via AWS CLI)."
  type        = string
  default     = ""
}

variable "new_relic_license_key" {
  description = "License key (ingest) do New Relic (ADR-0007). Vazia (padrão) mantém as duas Lambdas sem instrumentação — handler e layer originais, sem variáveis NEW_RELIC_*."
  type        = string
  sensitive   = true
  default     = ""
}

variable "new_relic_account_id" {
  description = "Account ID do New Relic (ADR-0007). Usado nas variáveis de ambiente das Lambdas quando new_relic_license_key está preenchida. A integração AWS↔New Relic para RDS/API Gateway (mesmo account ID, mais a user API key) fica num Terraform root separado — ver newrelic-aws-integration/."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags adicionais aplicadas aos recursos AWS."
  type        = map(string)
  default     = {}
}
