# newrelic-aws-integration

Terraform root **separado** de [`../terraform`](../terraform) — liga a conta AWS ao New Relic para cobrir **RDS** e **API Gateway** via a integração de nuvem AWS do New Relic (item 4 do [ADR-0007](https://github.com/phantosmia/oficina-mecanica-fiap/blob/main/docs/adrs/0007-new-relic-como-plataforma-de-observabilidade.md)).

## Por que um root separado, e não parte de `../terraform`

O provider `newrelic` precisa de credenciais próprias (uma **user API key**, diferente da license key usada pelos agentes) e Terraform não permite `count`/`for_each` num `module` que declara sua própria configuração de provider ("legacy module"). Manter isso como um root à parte, aplicado manualmente só por quem de fato quiser essa integração ativa, evita que `../terraform` (que todo mundo aplica, só pra ter a Lambda de autenticação) passe a exigir uma user API key configurada.

## ⚠️ Não funciona em AWS Academy Lab

Essa integração exige criar uma IAM role com uma trust policy que confia na conta AWS do New Relic (`754728514883`, condicionada a `sts:ExternalId`) — e o AWS Academy Lab bloqueia `iam:CreateRole`. Diferente de outras partes deste projeto (Lambdas, EKS), aqui **não existe uma role pré-criada do Lab pra reaproveitar**: a `LabRole` do Lab tem uma trust policy fixa, controlada pela Academy, que só confia em serviços AWS (`ec2.amazonaws.com`, `lambda.amazonaws.com` etc.) — nunca numa conta de terceiro como a do New Relic. Editar essa trust policy também não é uma opção viável no Lab.

Isso é uma limitação estrutural da conta, não um bug — mesma categoria da limitação já documentada para o AWS Load Balancer Controller/External Secrets Operator (`enable_irsa_resources=false` em `oficina-mecanica-infra-kubernetes`), que também exigem criar IAM que o Lab não permite.

**Em uma conta AWS normal** (fora do Lab), isso funciona: preencha `newrelic_integrations_role_arn` com o ARN de uma role já existente com a trust policy certa, ou deixe vazio para o próprio Terraform criar a role (exige `iam:CreateRole`).

## Uso

```bash
cp backend.hcl.example backend.hcl       # mesmo backend do ../terraform
cp terraform.tfvars.example terraform.tfvars

terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

## Variáveis e outputs

Ver [`variables.tf`](variables.tf) e [`outputs.tf`](outputs.tf).
