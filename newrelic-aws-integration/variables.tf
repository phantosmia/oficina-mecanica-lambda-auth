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
  description = "Região AWS onde a IAM role é criada."
  type        = string
  default     = "us-east-1"
}

variable "new_relic_account_id" {
  description = "Account ID do New Relic. Usado tanto para autenticar o provider quanto como sts:ExternalId na trust policy da role assumida."
  type        = string
}

variable "new_relic_api_key" {
  description = "User API key do New Relic (prefixo NRAK-) — diferente da license key (ingest) usada pelos agentes (oficina-mecanica-fiap, oficina-mecanica-lambda-auth). Usada pelo provider Terraform pra criar os recursos de integração via API."
  type        = string
  sensitive   = true
}

variable "new_relic_region" {
  description = "Região da conta New Relic (US ou EU)."
  type        = string
  default     = "US"
}

variable "newrelic_integrations_role_arn" {
  description = "ARN de uma IAM role já existente, com a trust policy documentada (principal arn:aws:iam::754728514883:root, condição sts:ExternalId = new_relic_account_id), para o New Relic assumir. Vazio (padrão) cria uma role própria — não funciona em AWS Academy Lab, que bloqueia iam:CreateRole e não permite editar a trust policy da LabRole para confiar numa conta de terceiro. Sem uma role pré-existente com essa trust policy, esta integração específica (RDS/API Gateway) não é viável em AWS Academy Lab — ver README."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags adicionais aplicadas aos recursos AWS."
  type        = map(string)
  default     = {}
}
