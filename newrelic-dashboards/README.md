# newrelic-dashboards

Terraform root **separado** de [`../terraform`](../terraform) e de [`../newrelic-aws-integration`](../newrelic-aws-integration) — cria o dashboard exigido pelo PDF da Fase 3 ("Monitoramento e Observabilidade" → "Expor dashboards com [...]"), via `newrelic_one_dashboard` (mesmo motivo de root próprio dos outros dois: o provider `newrelic` precisa de config própria, incompatível com `count`/`for_each` num `module`).

## O que o dashboard cobre

Três páginas:

1. **Ordens de Serviço** — os três itens literais do PDF: volume diário de OS, tempo médio de execução por status (Diagnóstico/Execução/Finalização), e uma tabela de ordens rejeitadas. Dado de `ServiceOrderCreated`/`ServiceOrderStatusChanged`, eventos customizados emitidos por `app/shared/telemetry.py` (`oficina-mecanica-fiap`) — a APM não sabe nada sobre esse domínio de negócio sozinha, por isso a instrumentação manual (ver PR que adicionou `app/shared/telemetry.py`).
2. **APIs & Infraestrutura** — latência e throughput da API (Transaction, APM), uptime do `/health`, CPU/memória por pod (`K8sContainerSample`, New Relic Kubernetes integration).
3. **Erros & Falhas nas Integrações** — taxa de erro e erros por tipo da API (`TransactionError`), e erros das duas Lambdas de autenticação (`AwsLambdaInvocation`, faceted por `name`).

Todas as queries foram validadas contra a conta real via NerdGraph antes de escrever o Terraform (não são nomes de atributo chutados) — rode as mesmas consultas em `https://one.newrelic.com/query-your-data` se quiser conferir.

## Pré-requisitos

Para os dados aparecerem de verdade, os três outros pilares do ADR-0007 precisam já estar aplicados: APM na aplicação principal (`oficina-mecanica-fiap`, PR de `NEW_RELIC_LICENSE_KEY`), a integração Kubernetes (`oficina-mecanica-infra-kubernetes`, `nri-bundle`) e a Lambda layer (`oficina-mecanica-lambda-auth`, `../terraform`). O dashboard em si não depende disso pra ser *criado* — só fica com os widgets vazios até esses três estarem no ar.

## Uso

```bash
cp backend.hcl.example backend.hcl       # mesmo backend do ../terraform
cp terraform.tfvars.example terraform.tfvars

terraform init -backend-config=backend.hcl
terraform plan
terraform apply

terraform output -raw dashboard_url      # abre o dashboard direto
```

## Variáveis e outputs

Ver [`variables.tf`](variables.tf) e [`outputs.tf`](outputs.tf).
