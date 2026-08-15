"""Configuração das Lambdas via variáveis de ambiente.

Os valores (senha do RDS, `JWT_SECRET_KEY`) são lidos pelo Terraform do
AWS Secrets Manager em tempo de `apply` (via `data.aws_secretsmanager_secret_version`,
ver `terraform/main.tf`) e injetados como variável de ambiente da função —
o mesmo padrão já usado por `infra/aws/main.tf` no repositório principal
(que também grava `POSTGRES_PASSWORD` lido do state remoto do banco direto
no Secrets Manager da API). Não há chamada de rede a segredos em tempo de
execução: a função `authenticate` só precisa alcançar o RDS (dentro da
VPC do banco); a função `authorizer` não faz nenhuma chamada de rede.
"""

import os
from dataclasses import dataclass


@dataclass(frozen=True)
class DbSettings:
    host: str
    port: int
    dbname: str
    username: str
    password: str


@dataclass(frozen=True)
class JwtSettings:
    secret_key: str
    algorithm: str
    access_token_expire_minutes: int


def load_db_settings() -> DbSettings:
    return DbSettings(
        host=os.environ["PGHOST"],
        port=int(os.environ["PGPORT"]),
        dbname=os.environ["PGDATABASE"],
        username=os.environ["PGUSER"],
        password=os.environ["PGPASSWORD"],
    )


def load_jwt_settings() -> JwtSettings:
    return JwtSettings(
        secret_key=os.environ["JWT_SECRET_KEY"],
        algorithm=os.environ.get("JWT_ALGORITHM", "HS256"),
        access_token_expire_minutes=int(os.environ.get("ACCESS_TOKEN_EXPIRE_MINUTES", "30")),
    )
