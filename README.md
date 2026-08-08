# oficina-mecanica-lambda-auth

Function Serverless (AWS Lambda) de **autenticação via CPF** do sistema de gestão de oficina mecânica — repositório 1 dos 4 exigidos pela Fase 3 do Tech Challenge (SOAT/FIAP).

> **Status: Placeholder.** Implementação real pendente — este repositório existe para fixar a estrutura (código, CI/CD, branches, proteção) enquanto a implementação é feita com calma em uma etapa futura.

## Propósito futuro

Rotas sensíveis da aplicação principal serão protegidas por um **AWS API Gateway**, que delega a autenticação do cliente a esta Lambda. O fluxo planejado:

1. Validar o CPF informado pelo cliente.
2. Consultar a existência e o status do cliente na base de dados.
3. Gerar e devolver um **JWT** válido para consumo das APIs protegidas.

Essa decisão de arquitetura já está documentada no repositório da aplicação principal:

- [RFC-0004 — Escolha da solução de API Gateway](https://github.com/phantosmia/oficina-mecanica-fiap/blob/main/docs/rfcs/0004-escolha-do-api-gateway.md)
- [ADR-0004 — API Gateway como ponto único de entrada e autorização](https://github.com/phantosmia/oficina-mecanica-fiap/blob/main/docs/adrs/0004-api-gateway-como-ponto-de-entrada.md)

## Tecnologias planejadas

- Python (AWS Lambda)
- AWS API Gateway (Lambda proxy integration / Lambda Authorizer)
- PyJWT (ou equivalente) para emissão do token
- Terraform para provisionamento (repositório próprio ou compartilhado com a infra Kubernetes — a definir)

## Estrutura atual

```text
src/handler.py     # stub — levanta NotImplementedError
requirements.txt   # vazio por enquanto
tests/              # vazio por enquanto
```

## CI/CD

Workflow em [`.github/workflows/ci.yml`](.github/workflows/ci.yml):

- **Pull Request** e **push**: valida apenas a sintaxe do stub (`python -m py_compile src/handler.py`) — não há lógica real para testar ainda.
- **Push para `homologacao`/`producao`**: job `deploy-placeholder` que apenas imprime um aviso de que a implementação real está pendente. Nenhum recurso é implantado.

### Regras de proteção

- Branch `main` protegida: sem commit direto, merge só via Pull Request.

## Repositórios relacionados

- [oficina-mecanica-fiap](https://github.com/phantosmia/oficina-mecanica-fiap) — aplicação principal.
- [oficina-mecanica-infra-banco-dados](https://github.com/phantosmia/oficina-mecanica-infra-banco-dados) — banco de dados gerenciado (implementação real).
- [oficina-mecanica-infra-kubernetes](https://github.com/phantosmia/oficina-mecanica-infra-kubernetes) — infraestrutura Kubernetes.
