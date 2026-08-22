variable "new_relic_account_id" {
  description = "Account ID do New Relic."
  type        = string
}

variable "new_relic_api_key" {
  description = "User API key do New Relic (prefixo NRAK-) — diferente da license key (ingest) usada pelos agentes."
  type        = string
  sensitive   = true
}

variable "new_relic_region" {
  description = "Região da conta New Relic (US ou EU)."
  type        = string
  default     = "US"
}

variable "app_name" {
  description = "NEW_RELIC_APP_NAME configurado na aplicação principal (k8s/base/configmap.yaml, oficina-mecanica-fiap)."
  type        = string
  default     = "oficina-mecanica-api"
}

variable "kubernetes_namespace" {
  description = "Namespace Kubernetes onde a aplicação principal roda."
  type        = string
  default     = "oficina-mecanica"
}

variable "api_container_name" {
  description = "Nome do container da aplicação principal (k8s/base/api.yaml)."
  type        = string
  default     = "api"
}
