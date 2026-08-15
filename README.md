# oficina-mecanica-lambda-auth

Function Serverless (AWS Lambda) de **autenticação via CPF** do sistema de gestão de oficina mecânica — repositório 1 dos 4 exigidos pela Fase 3 do Tech Challenge (SOAT/FIAP).

Valida o CPF informado pelo cliente, consulta a existência do cliente no banco de dados gerenciado (RDS PostgreSQL, provisionado pelo repositório [`oficina-mecanica-infra-banco-dados`](https://github.com/phantosmia/oficina-mecanica-infra-banco-dados)) e emite um **JWT** compatível com o mecanismo de autenticação já usado pela [aplicação principal](https://github.com/phantosmia/oficina-mecanica-fiap) (`app/shared/security.py`), consumível como `Authorization: Bearer <token>` nas rotas protegidas.

Essa decisão de arquitetura está documentada no repositório da aplicação principal:

- [RFC-0004 — Escolha da solução de API Gateway](https://github.com/phantosmia/oficina-mecanica-fiap/blob/main/docs/rfcs/0004-escolha-do-api-gateway.md)
- [ADR-0004 — API Gateway como ponto único de entrada e autorização](https://github.com/phantosmia/oficina-mecanica-fiap/blob/main/docs/adrs/0004-api-gateway-como-ponto-de-entrada.md)
- [ADR-0005 — Lambda de autenticação na VPC do banco de dados](https://github.com/phantosmia/oficina-mecanica-fiap/blob/main/docs/adrs/0005-lambda-auth-na-vpc-do-banco.md)

## Arquitetura

```mermaid
flowchart LR
    Cliente(["Cliente da oficina"]) -->|"POST /auth/cpf<br/>{ cpf }"| APIGW["AWS API Gateway<br/>(HTTP API)"]
    APIGW --> AuthFn["Lambda: authenticate<br/>(dentro da VPC do banco)"]
    AuthFn -->|"SELECT ... WHERE<br/>document_number = :cpf"| RDS[("Amazon RDS<br/>PostgreSQL")]
    AuthFn -->|"JWT (sub=cpf,<br/>type=client)"| Cliente

    Cliente -->|"rota protegida<br/>Authorization: Bearer"| APIGW
    APIGW --> AuthzFn["Lambda: authorizer<br/>(fora de VPC)"]
    AuthzFn -->|"isAuthorized"| APIGW
    APIGW -.->|"proxy (próximo passo,<br/>ver 'Limitações conhecidas')"| EKS["Cluster EKS<br/>(oficina-mecanica-fiap)"]
```

Duas funções Lambda, empacotadas a partir do mesmo código (`src/`), com responsabilidades e necessidades de rede diferentes:

| Função | Handler | Rede | Faz o quê |
|---|---|---|---|
| `authenticate` | `handler.authenticate_handler` | Dentro da VPC do banco (`oficina-mecanica-infra-banco-dados`) | Valida o CPF, consulta `clients` no RDS, emite o JWT |
| `authorizer` | `handler.authorizer_handler` | Fora de VPC | Lambda Authorizer (`REQUEST`, respostas simples) do API Gateway — valida o JWT em rotas protegidas |

## Tecnologias

- Python 3.12 (runtime AWS Lambda)
- [PyJWT](https://pyjwt.readthedocs.io/) — emissão/validação do JWT (compatível com `python-jose`, usado pela aplicação principal, para tokens HS256)
- [pg8000](https://github.com/tlocke/pg8000) — driver PostgreSQL 100% Python (sem extensão C, evita o problema de compilar `psycopg2` para o runtime do Lambda)
- AWS API Gateway (HTTP API) + Lambda Authorizer
- Terraform >= 1.6
- GitHub Actions

## Estrutura do repositório

```text
src/
  handler.py       # entrypoints: authenticate_handler, authorizer_handler
  cpf.py           # validação de CPF (sem dependências externas)
  db.py            # consulta a clients no RDS via pg8000
  jwt_utils.py      # emissão/validação do JWT (PyJWT)
  settings.py       # leitura de configuração via variável de ambiente
tests/              # pytest — 100% dos testes usam mocks, sem rede real
terraform/          # Lambda, IAM, API Gateway, integração via terraform_remote_state
```

## Endpoint de autenticação

`POST /auth/cpf`

```json
// Requisição
{ "cpf": "529.982.247-25" }
```

```json
// 200 — cliente encontrado
{ "access_token": "eyJhbGciOiJIUzI1NiIs...", "token_type": "bearer" }
```

```json
// 400 — CPF ausente, mal formatado ou com dígito verificador inválido
{ "detail": "CPF inválido." }
```

```json
// 404 — CPF válido, mas sem cliente cadastrado (ver "Cliente inexistente vs. inativo" abaixo)
{ "detail": "Cliente não encontrado ou inativo para este CPF." }
```

O JWT emitido tem o mesmo formato de claims (`sub`, `exp`) que `create_access_token` na aplicação principal — `sub` é o CPF (dígitos, sem máscara) e há uma claim extra `type: "client"` (mais `client_id`) para a aplicação principal poder diferenciar, no futuro, um token de cliente de um token de administrador (ver "Limitações conhecidas").

### Cliente inexistente vs. inativo

A tabela `clients` da aplicação principal não tem hoje uma coluna de status explícita (só `id`, `name`, `document_type`, `document_number`, `email`, `phone`) — ver [`app/shared/models.py`](https://github.com/phantosmia/oficina-mecanica-fiap/blob/main/app/shared/models.py). Por isso, "consultar a existência e o status do cliente" (requisito da Fase 3) hoje se resume a "o registro existe": não há como diferenciar um cliente inativo de um cliente inexistente sem uma mudança de schema na aplicação principal, fora do escopo deste repositório.

## Uso local

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements-dev.txt

pytest tests/ -v
```

Os testes mockam toda chamada externa (RDS, geração de JWT usa um segredo de teste) — nenhum teste depende de rede ou de uma AWS real.

## Terraform / Deploy

```bash
cd terraform
cp backend.hcl.example backend.hcl           # ajuste bucket/tabela (mesmo backend do oficina-mecanica-fiap)
cp terraform.tfvars.example terraform.tfvars

terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

O `apply` instala `requirements.txt` num diretório `terraform/build/` (via `null_resource` + `local-exec`) e empacota `src/*.py` junto num `.zip` (`data.archive_file`) — não é necessário buildar o pacote manualmente antes.

## Integração com os outros repositórios (via `terraform_remote_state`)

Este repositório lê, do mesmo backend S3 compartilhado pelos quatro repositórios da Fase 3:

- `oficina-mecanica-infra-banco-dados`: `vpc_id`, `private_subnet_ids` (para colocar a função `authenticate` na mesma VPC do RDS) e `rds_secret_arn` (host/porta/banco/usuário/senha do PostgreSQL).
- `oficina-mecanica-fiap` (`infra/aws`): `app_secret_arn` (de onde vem o `JWT_SECRET_KEY` — o **mesmo** segredo que a aplicação principal usa para validar o token).

```mermaid
flowchart LR
    DB["oficina-mecanica-infra-banco-dados"] -- "vpc_id, private_subnet_ids,<br/>rds_secret_arn" --> LAMBDA["este repositório"]
    APP["oficina-mecanica-fiap: infra/aws"] -- "app_secret_arn<br/>(JWT_SECRET_KEY)" --> LAMBDA
```

**Isso estabelece uma nova posição na ordem de apply da Fase 3**: banco de dados → cluster Kubernetes → aplicação principal (`infra/aws`) → **esta Lambda** (ver o [diagrama de dependência completo](https://github.com/phantosmia/oficina-mecanica-fiap/blob/main/docs/arquitetura.md#diagrama-de-dependência-entre-os-repositórios-terraform) no repositório principal). Se o state do ambiente lido (`dev`, `homologacao` ou `producao`) ainda não existir em algum dos dois repositórios acima, o `plan`/`apply` deste repositório falha imediatamente com `Unable to find remote state` — o mesmo comportamento já documentado nos outros repositórios, não um bug.

### Por que a Lambda `authenticate` reside na VPC do banco

O RDS não é publicamente acessível (`publicly_accessible = false`) e sua VPC não tem Internet Gateway/NAT. Colocar a função `authenticate` nas mesmas subnets privadas (via `private_subnet_ids`) evita expor o banco publicamente ou criar um NAT Gateway só para isso — ver [ADR-0005](https://github.com/phantosmia/oficina-mecanica-fiap/blob/main/docs/adrs/0005-lambda-auth-na-vpc-do-banco.md) para as alternativas consideradas.

Isso exige um passo manual: o security group do RDS (`oficina-mecanica-infra-banco-dados`) libera a porta 5432 por **CIDR** (`allowed_cidr_blocks`), não por security group. Inclua o CIDR da VPC do banco (`vpc_cidr` daquele repositório, `10.90.0.0/24` por padrão) em `allowed_cidr_blocks` antes de aplicar esta Lambda em um novo ambiente — do contrário, a conexão ao RDS terá timeout.

A função `authorizer` não faz nenhuma chamada de rede (o `JWT_SECRET_KEY` já chega via variável de ambiente, definida em tempo de `apply` — ver "Terraform / Deploy") e roda fora de VPC, evitando o custo/latência de ENI sem necessidade.

## CI/CD

Workflow em [`.github/workflows/ci.yml`](.github/workflows/ci.yml), com três jobs:

- **`test`** (sempre): `pytest tests/ -v`.
- **`plan`** (Pull Request, depois de `test`): `terraform fmt -check`, `validate` e `plan` (lê o state real `dev` dos outros repositórios — pode falhar com `Unable to find remote state` se esse ambiente ainda não existir, ver acima).
- **`apply`** (push para `homologacao`/`producao`, depois de `test`): `init` com backend remoto (`lambda/<branch>/terraform.tfstate`), `plan` e `apply` automático.

### Regras de proteção

- Branch `main` protegida: sem commit direto, merge só via Pull Request.
- `homologacao` e `producao` disparam `apply` automático no push (ambientes GitHub `homologacao`/`producao`, permitindo configurar secrets/aprovações por ambiente).

### Secrets e variables necessários

| Tipo | Nome | Descrição |
|---|---|---|
| Secret | `AWS_ACCESS_KEY_ID` | Access key temporária do AWS Academy Lab |
| Secret | `AWS_SECRET_ACCESS_KEY` | Secret key temporária do AWS Academy Lab |
| Secret | `AWS_SESSION_TOKEN` | Session token temporário do AWS Academy Lab |
| Secret | `TF_BACKEND_CONFIG` | Conteúdo completo de um `backend.hcl` (alternativa às variables abaixo) |
| Variable | `AWS_REGION` | Região AWS |
| Variable | `TF_STATE_BUCKET` | Bucket S3 do state (mesmo do `oficina-mecanica-fiap`) |
| Variable | `TF_LOCK_TABLE` | Tabela DynamoDB de lock (mesma do `oficina-mecanica-fiap`) |
| Variable | `TF_STATE_REGION` | Região do backend S3 |

## Variáveis e outputs

Ver [`terraform/variables.tf`](terraform/variables.tf) e [`terraform/outputs.tf`](terraform/outputs.tf) para a lista completa, com descrições.

## Limitações conhecidas / próximos passos

- **Proxy das rotas sensíveis ao EKS**: o `aws_apigatewayv2_authorizer` (`jwt_client`) está criado e pronto para uso, mas nenhuma rota deste API Gateway proxeia ainda para o cluster EKS — isso exige o DNS do Load Balancer/Ingress da aplicação principal, que hoje não é um output do Terraform (é criado em tempo de admissão pelo AWS Load Balancer Controller a partir de um recurso `Ingress` do Kubernetes, não por um recurso Terraform). Fica para uma etapa futura.
- **Diferenciação de token na aplicação principal**: `app/shared/dependencies.py::get_current_admin` hoje só aceita `sub == settings.admin_username`; um JWT de cliente emitido por esta Lambda (`sub` = CPF, `type: "client"`) seria rejeitado por qualquer rota que dependa dele. Adaptar a aplicação principal para aceitar e diferenciar os dois tipos de token (ver ADR-0004, "a aplicação precisa continuar aceitando e diferenciando esses formatos por tipo de rota") é um trabalho do repositório `oficina-mecanica-fiap`, fora do escopo deste repositório.
- **Status do cliente**: ver "Cliente inexistente vs. inativo" acima.

## Repositórios relacionados

- [oficina-mecanica-fiap](https://github.com/phantosmia/oficina-mecanica-fiap) — aplicação principal.
- [oficina-mecanica-infra-banco-dados](https://github.com/phantosmia/oficina-mecanica-infra-banco-dados) — banco de dados gerenciado.
- [oficina-mecanica-infra-kubernetes](https://github.com/phantosmia/oficina-mecanica-infra-kubernetes) — infraestrutura Kubernetes.
