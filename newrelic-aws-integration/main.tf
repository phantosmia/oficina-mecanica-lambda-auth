# Terraform root separado (não módulo do ../terraform) de propósito: o
# provider "newrelic" precisa de credenciais próprias (user API key,
# diferente da license key usada pelos agentes), e Terraform não permite
# count/for_each num "module" que declara sua própria configuração de
# provider ("legacy module"). Manter isso como um root à parte, aplicado
# manualmente quando alguém de fato quiser essa integração ativa, evita
# que ../terraform (que todo mundo aplica) dependa de ter uma user API key
# configurada — mesmo padrão de "root Terraform separado e opcional" já
# usado em oficina-mecanica-fiap (infra/backend vs. infra/aws).
#
# Liga a conta AWS ao New Relic (ADR-0007) para cobrir RDS e API Gateway via
# a integração de nuvem "PULL" (polling periódico contra a API do CloudWatch)
# — não a "PUSH" via CloudWatch Metric Streams, que exigiria montar um
# pipeline próprio (Kinesis Data Firehose + bucket S3 de backup) só pra
# reduzir a latência de alguns minutos num projeto de curso. A trust policy
# abaixo (conta AWS 754728514883, condicionada a sts:ExternalId) é a
# documentada pelo provider oficial (registry.terraform.io/providers/
# newrelic/newrelic, guia "Cloud integrations") para o New Relic assumir
# a role.
locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Course      = "FIAP"
      Component   = "newrelic-aws-integration"
    },
    var.tags,
  )
}

data "aws_iam_policy_document" "newrelic_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::754728514883:root"]
    }

    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [var.new_relic_account_id]
    }
  }
}

resource "aws_iam_role" "newrelic_integrations" {
  count = var.newrelic_integrations_role_arn == "" ? 1 : 0

  name               = "${local.name_prefix}-newrelic-integrations"
  assume_role_policy = data.aws_iam_policy_document.newrelic_assume_role.json

  tags = local.common_tags
}

locals {
  newrelic_role_arn = var.newrelic_integrations_role_arn != "" ? var.newrelic_integrations_role_arn : aws_iam_role.newrelic_integrations[0].arn
}

# Só leitura, e escopada só ao que os dois integrations habilitados abaixo
# (rds, api_gateway) de fato precisam — mais estreita que o exemplo padrão
# do New Relic (que cobre dezenas de serviços), de propósito: não habilitamos
# integrations além de RDS/API Gateway.
data "aws_iam_policy_document" "newrelic_integrations" {
  statement {
    sid = "CloudWatchMetrics"
    actions = [
      "cloudwatch:GetMetricData",
      "cloudwatch:GetMetricStatistics",
      "cloudwatch:ListMetrics",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "ResourceTags"
    actions   = ["tag:GetResources"]
    resources = ["*"]
  }

  statement {
    sid = "RdsDescribe"
    actions = [
      "rds:DescribeDBInstances",
      "rds:DescribeDBClusters",
      "rds:ListTagsForResource",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "ApiGatewayRead"
    actions   = ["apigateway:GET"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "newrelic_integrations" {
  count = var.newrelic_integrations_role_arn == "" ? 1 : 0

  name   = "${local.name_prefix}-newrelic-integrations"
  role   = aws_iam_role.newrelic_integrations[0].id
  policy = data.aws_iam_policy_document.newrelic_integrations.json
}

resource "newrelic_cloud_aws_link_account" "this" {
  arn                    = local.newrelic_role_arn
  metric_collection_mode = "PULL"
  name                   = "${local.name_prefix}-aws"
}

resource "newrelic_cloud_aws_integrations" "this" {
  linked_account_id = newrelic_cloud_aws_link_account.this.id

  rds {}

  api_gateway {}
}
