# Lê automaticamente, via terraform_remote_state contra o mesmo backend S3
# compartilhado pelos quatro repositórios da Fase 3, os outputs de que esta
# Lambda depende: rede + secret do RDS (oficina-mecanica-infra-banco-dados)
# e o secret com o JWT_SECRET_KEY da aplicação principal (oficina-mecanica-fiap,
# infra/aws). Isso elimina a necessidade de copiar esses valores manualmente
# a cada apply daqueles repositórios — mesmo padrão já usado entre os outros
# três repositórios da Fase 3 (ver docs/arquitetura.md do repositório principal).
data "terraform_remote_state" "database" {
  backend = "s3"

  config = {
    bucket = var.tf_state_bucket
    key    = var.database_state_key
    region = var.tf_state_region
  }
}

data "terraform_remote_state" "app" {
  backend = "s3"

  config = {
    bucket = var.tf_state_bucket
    key    = var.app_state_key
    region = var.tf_state_region
  }
}

# Usado só pela rota proxy ao EKS (VPC Link, ver "Proxy para o cluster EKS"
# abaixo) — para colocar o VPC Link na mesma VPC/subnets privadas do ALB
# (agora interno, ADR-0006).
data "terraform_remote_state" "kubernetes" {
  backend = "s3"

  config = {
    bucket = var.tf_state_bucket
    key    = var.kubernetes_state_key
    region = var.tf_state_region
  }
}

# Lidas em tempo de apply e injetadas como variável de ambiente das Lambdas
# (ver locals.rds_connection / locals.jwt_secret_key abaixo) — o mesmo padrão
# já usado por infra/aws/main.tf no repositório principal, que grava
# POSTGRES_PASSWORD (lido do state remoto do banco) direto no secret da API.
# O provider da AWS marca o atributo `secret_string` destes data sources como
# sensível, então os valores não aparecem em texto puro no output do
# `terraform plan`/`apply`.
data "aws_secretsmanager_secret_version" "rds" {
  secret_id = data.terraform_remote_state.database.outputs.rds_secret_arn
}

data "aws_secretsmanager_secret_version" "app" {
  secret_id = data.terraform_remote_state.app.outputs.app_secret_arn
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  rds_connection = jsondecode(data.aws_secretsmanager_secret_version.rds.secret_string)
  jwt_secret_key = jsondecode(data.aws_secretsmanager_secret_version.app.secret_string)["JWT_SECRET_KEY"]

  lambda_role_arn = var.lambda_execution_role_arn != "" ? var.lambda_execution_role_arn : aws_iam_role.lambda[0].arn

  # ADR-0007: instrumentação via New Relic Lambda layer, em vez de importar
  # um SDK em src/handler.py — troca de vendor de observabilidade no futuro
  # não exige tocar no código da Lambda. Layer x86_64 (arquitetura default
  # de aws_lambda_function quando `architectures` não é especificado); ARN
  # da versão atual obtida em tempo de escrita via a API pública do New
  # Relic (https://<region>.layers.newrelic-external.com/get-layers), não
  # existe data source oficial do provider AWS/New Relic pra isso.
  # nonsensitive(): só o booleano "está preenchida ou não" deixa de herdar a
  # sensibilidade de var.new_relic_license_key — sem isso, handler/layers
  # (que não contêm segredo nenhum) apareceriam como "(sensitive value)" no
  # plan só por serem derivados de uma expressão que referencia a variável.
  new_relic_enabled   = nonsensitive(var.new_relic_license_key != "")
  new_relic_layer_arn = "arn:aws:lambda:${var.aws_region}:451483290750:layer:NewRelicPython312:80"

  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Course      = "FIAP"
      Component   = "lambda-auth"
    },
    var.tags,
  )
}

# --- Empacotamento -----------------------------------------------------
# As duas dependências (PyJWT, pg8000) são wheels puramente Python (sem
# extensão C), então instalar em qualquer SO produz um pacote compatível
# com o runtime do Lambda — sem necessidade de --platform/--only-binary.
# Se uma futura dependência exigir extensão nativa, adicione essas flags.
resource "null_resource" "build" {
  triggers = {
    requirements_hash = filesha256("${path.module}/../requirements.txt")
    src_hash = sha256(join("", [
      for f in sort(fileset("${path.module}/../src", "*.py")) : filesha256("${path.module}/../src/${f}")
    ]))
  }

  provisioner "local-exec" {
    # local-exec roda via /bin/sh, que em muitos sistemas (Debian/Ubuntu,
    # inclusive os runners do GitHub Actions) é dash, não bash — "pipefail"
    # é bashismo e dash rejeita com "Illegal option -o pipefail". O script
    # não usa nenhum pipe (|), então "pipefail" nunca fez diferença aqui;
    # "set -eu" já é suficiente e é POSIX (funciona em qualquer /bin/sh).
    command = <<-EOT
      set -eu
      rm -rf "${path.module}/build"
      mkdir -p "${path.module}/build"
      pip install --quiet -r "${path.module}/../requirements.txt" -t "${path.module}/build" --no-cache-dir
      cp "${path.module}"/../src/*.py "${path.module}/build/"
    EOT
  }
}

data "archive_file" "package" {
  type        = "zip"
  source_dir  = "${path.module}/build"
  output_path = "${path.module}/build.zip"

  depends_on = [null_resource.build]
}

# --- IAM -----------------------------------------------------------------
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  count = var.lambda_execution_role_arn == "" ? 1 : 0

  name               = "${local.name_prefix}-lambda-auth"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = local.common_tags
}

# Cobre logs (CloudWatch) e o gerenciamento de ENI necessário para a função
# `authenticate`, que roda dentro da VPC do banco para alcançar o RDS —
# anexada também na função `authorizer` por simplicidade (permissão ociosa
# e inofensiva para quem não usa VPC).
resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  count = var.lambda_execution_role_arn == "" ? 1 : 0

  role       = aws_iam_role.lambda[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# --- Rede ------------------------------------------------------------------
# A função `authenticate` roda na mesma VPC/subnets privadas do RDS (outputs
# do oficina-mecanica-infra-banco-dados) para alcançá-lo sem expô-lo
# publicamente. Isso exige que `allowed_cidr_blocks` naquele repositório
# inclua o CIDR dessa VPC (`var.vpc_cidr` de lá) — ver README, seção
# "Integração com os outros repositórios". A função `authorizer` não faz
# nenhuma chamada de rede (o segredo já chega via variável de ambiente) e
# roda fora de VPC, evitando o custo/latência de ENI sem necessidade.
resource "aws_security_group" "lambda_authenticate" {
  name        = "${local.name_prefix}-lambda-auth"
  description = "Saida da Lambda de autenticacao (CPF) em direcao ao RDS"
  vpc_id      = data.terraform_remote_state.database.outputs.vpc_id

  egress {
    description = "Todo trafego de saida (inclui PostgreSQL para o RDS)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}

# --- Lambdas -----------------------------------------------------------
resource "aws_cloudwatch_log_group" "authenticate" {
  name              = "/aws/lambda/${local.name_prefix}-auth-cpf"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

resource "aws_lambda_function" "authenticate" {
  function_name = "${local.name_prefix}-auth-cpf"
  description   = "Valida CPF, consulta o cliente no RDS e emite um JWT (RFC-0004 / ADR-0004 do oficina-mecanica-fiap)."

  filename         = data.archive_file.package.output_path
  source_code_hash = data.archive_file.package.output_base64sha256

  handler = local.new_relic_enabled ? "newrelic_lambda_wrapper.handler" : "handler.authenticate_handler"
  runtime = "python3.12"
  role    = local.lambda_role_arn
  layers  = local.new_relic_enabled ? [local.new_relic_layer_arn] : []

  memory_size = var.lambda_memory_size
  timeout     = var.lambda_timeout

  vpc_config {
    subnet_ids         = data.terraform_remote_state.database.outputs.private_subnet_ids
    security_group_ids = [aws_security_group.lambda_authenticate.id]
  }

  environment {
    variables = merge(
      {
        PGHOST                      = local.rds_connection.host
        PGPORT                      = tostring(local.rds_connection.port)
        PGDATABASE                  = local.rds_connection.dbname
        PGUSER                      = local.rds_connection.username
        PGPASSWORD                  = local.rds_connection.password
        JWT_SECRET_KEY              = local.jwt_secret_key
        JWT_ALGORITHM               = var.jwt_algorithm
        ACCESS_TOKEN_EXPIRE_MINUTES = tostring(var.access_token_expire_minutes)
      },
      local.new_relic_enabled ? {
        NEW_RELIC_LAMBDA_HANDLER = "handler.authenticate_handler"
        NEW_RELIC_LICENSE_KEY    = var.new_relic_license_key
        NEW_RELIC_ACCOUNT_ID     = var.new_relic_account_id
        NEW_RELIC_APP_NAME       = "${local.name_prefix}-auth-cpf"
      } : {}
    )
  }

  tags = local.common_tags

  depends_on = [aws_cloudwatch_log_group.authenticate]
}

resource "aws_cloudwatch_log_group" "authorizer" {
  name              = "/aws/lambda/${local.name_prefix}-auth-authorizer"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

resource "aws_lambda_function" "authorizer" {
  function_name = "${local.name_prefix}-auth-authorizer"
  description   = "Lambda Authorizer do API Gateway: valida o JWT de cliente emitido pela funcao authenticate."

  filename         = data.archive_file.package.output_path
  source_code_hash = data.archive_file.package.output_base64sha256

  handler = local.new_relic_enabled ? "newrelic_lambda_wrapper.handler" : "handler.authorizer_handler"
  runtime = "python3.12"
  role    = local.lambda_role_arn
  layers  = local.new_relic_enabled ? [local.new_relic_layer_arn] : []

  memory_size = var.lambda_memory_size
  timeout     = var.lambda_timeout

  environment {
    variables = merge(
      {
        JWT_SECRET_KEY = local.jwt_secret_key
        JWT_ALGORITHM  = var.jwt_algorithm
      },
      local.new_relic_enabled ? {
        NEW_RELIC_LAMBDA_HANDLER = "handler.authorizer_handler"
        NEW_RELIC_LICENSE_KEY    = var.new_relic_license_key
        NEW_RELIC_ACCOUNT_ID     = var.new_relic_account_id
        NEW_RELIC_APP_NAME       = "${local.name_prefix}-auth-authorizer"
      } : {}
    )
  }

  tags = local.common_tags

  depends_on = [aws_cloudwatch_log_group.authorizer]
}

# --- API Gateway (HTTP API) ---------------------------------------------
resource "aws_apigatewayv2_api" "main" {
  name          = "${local.name_prefix}-auth"
  protocol_type = "HTTP"
  description   = "API Gateway de autenticacao via CPF (RFC-0004 / ADR-0004 do oficina-mecanica-fiap)."

  tags = local.common_tags
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true

  tags = local.common_tags
}

resource "aws_apigatewayv2_integration" "authenticate" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.authenticate.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "authenticate" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "POST /auth/cpf"
  target    = "integrations/${aws_apigatewayv2_integration.authenticate.id}"
}

resource "aws_lambda_permission" "apigw_invoke_authenticate" {
  statement_id  = "AllowAPIGatewayInvokeAuthenticate"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.authenticate.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

# Authorizer REQUEST (respostas simples do HTTP API), usado pela rota proxy
# abaixo para proteger o acesso ao cluster EKS com o JWT de cliente.
resource "aws_apigatewayv2_authorizer" "jwt_client" {
  api_id                            = aws_apigatewayv2_api.main.id
  name                              = "${local.name_prefix}-jwt-client"
  authorizer_type                   = "REQUEST"
  authorizer_uri                    = aws_lambda_function.authorizer.invoke_arn
  authorizer_payload_format_version = "2.0"
  enable_simple_responses           = true
  identity_sources                  = ["$request.header.Authorization"]
}

resource "aws_lambda_permission" "apigw_invoke_authorizer" {
  statement_id  = "AllowAPIGatewayInvokeAuthorizer"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.authorizer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

# --- Proxy para o cluster EKS, via VPC Link ------------------------------
# O ALB do Ingress da aplicação principal (oficina-mecanica-fiap,
# k8s/overlays/aws) é `internal` (não internet-facing, ver ADR-0006) —
# só é alcançável de dentro da VPC do EKS. Este API Gateway passa a ser o
# único caminho de entrada público, alcançando o ALB via VPC Link (ENIs
# nas mesmas subnets privadas do cluster, lidas de
# data.terraform_remote_state.kubernetes).
#
# Diferente do proxy público simples (HTTP_PROXY com URL), uma integração
# privada via VPC Link aponta para o ARN do LISTENER do ALB, não para o seu
# DNS — outro valor que não é output de nenhum Terraform da Fase 3 (o ALB é
# criado em tempo de admissão pelo AWS Load Balancer Controller a partir do
# Ingress do Kubernetes). Populado manualmente via var.eks_alb_listener_arn
# depois que o Ingress existir:
#   ALB_ARN=$(aws elbv2 describe-load-balancers --query \
#     "LoadBalancers[?contains(DNSName, '<prefixo-do-hostname-do-ingress>')].LoadBalancerArn" -o text)
#   aws elbv2 describe-listeners --load-balancer-arn "$ALB_ARN" \
#     --query "Listeners[?Port==\`80\`].ListenerArn" -o text
# Enquanto a variável estiver vazia (padrão), o VPC Link e as duas rotas
# abaixo não são criados — o restante da Lambda funciona normalmente sem eles.
resource "aws_security_group" "vpc_link" {
  count = var.eks_alb_listener_arn != "" ? 1 : 0

  name        = "${local.name_prefix}-vpc-link"
  description = "Saida do VPC Link do API Gateway em direcao ao ALB interno do EKS"
  vpc_id      = data.terraform_remote_state.kubernetes.outputs.vpc_id

  egress {
    description = "Todo trafego de saida (inclui HTTP para o ALB interno)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}

resource "aws_apigatewayv2_vpc_link" "eks" {
  count = var.eks_alb_listener_arn != "" ? 1 : 0

  name               = "${local.name_prefix}-eks"
  subnet_ids         = data.terraform_remote_state.kubernetes.outputs.private_subnet_ids
  security_group_ids = [aws_security_group.vpc_link[0].id]

  tags = local.common_tags
}

resource "aws_apigatewayv2_integration" "eks_proxy" {
  count = var.eks_alb_listener_arn != "" ? 1 : 0

  api_id             = aws_apigatewayv2_api.main.id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"
  integration_uri    = var.eks_alb_listener_arn
  connection_type    = "VPC_LINK"
  connection_id      = aws_apigatewayv2_vpc_link.eks[0].id
}

# Rota geral, SEM o authorizer de CPF: login/rotas administrativas (que já
# têm sua própria proteção via JWT de admin, app/shared/dependencies.py::
# get_current_admin — um mecanismo totalmente diferente do JWT de cliente),
# o link de aprovação de orçamento por e-mail (token de uso único, não JWT)
# e o tracking sem token continuam alcançáveis, exatamente como quando o
# ALB ainda era público — só que agora via Gateway. PUBLIC_BASE_URL
# (usado no e-mail de orçamento, ver app/shared/email.py) deve apontar para
# a raiz deste API Gateway (output public_base_url), não mais para o ALB.
resource "aws_apigatewayv2_route" "eks_public_proxy" {
  count = var.eks_alb_listener_arn != "" ? 1 : 0

  api_id    = aws_apigatewayv2_api.main.id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.eks_proxy[0].id}"
}

# Rota mais específica (`/api/*` vence `/*` no roteamento do HTTP API),
# COM o authorizer de CPF — para quem quer a garantia extra de validação
# na borda antes mesmo de chegar à aplicação (ex.: tracking de OS).
resource "aws_apigatewayv2_route" "eks_proxy" {
  count = var.eks_alb_listener_arn != "" ? 1 : 0

  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "ANY /api/{proxy+}"
  target             = "integrations/${aws_apigatewayv2_integration.eks_proxy[0].id}"
  authorization_type = "CUSTOM"
  authorizer_id      = aws_apigatewayv2_authorizer.jwt_client.id
}
