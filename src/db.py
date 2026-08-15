"""Consulta ao PostgreSQL gerenciado (RDS) — apenas leitura da tabela `clients`.

Usa `pg8000` (driver PostgreSQL 100% Python) em vez de `psycopg2`: evita o
problema clássico de empacotar uma extensão C compilada para o runtime do
Lambda (Amazon Linux) a partir de uma máquina de desenvolvimento diferente.

A conexão é reaberta a cada invocação por simplicidade — um cache de conexão
em memória global (reaproveitando o container "quente") é uma otimização
possível, mas conexões PostgreSQL abertas indefinidamente em containers
Lambda reciclados sem aviso tendem a acumular conexões mortas no RDS; para o
volume de autenticação esperado aqui, abrir/fechar por invocação é a escolha
mais simples e segura.
"""

from dataclasses import dataclass

import pg8000.native

from settings import DbSettings


@dataclass(frozen=True)
class ClientRecord:
    id: int
    name: str
    document_number: str
    email: str | None


def find_client_by_document(db: DbSettings, document_number: str) -> ClientRecord | None:
    """Busca um cliente pelo CPF (dígitos, sem máscara).

    Retorna `None` se não existir nenhum cliente com esse `document_number`,
    que é a definição de "cliente inexistente ou inativo" hoje: a tabela
    `clients` do repositório principal não tem uma coluna de status
    explícita (ver README), então a própria existência do registro é o
    único sinal de status disponível.
    """
    connection = pg8000.native.Connection(
        user=db.username,
        password=db.password,
        host=db.host,
        port=db.port,
        database=db.dbname,
    )
    try:
        rows = connection.run(
            "SELECT id, name, document_number, email FROM clients WHERE document_number = :document_number",
            document_number=document_number,
        )
    finally:
        connection.close()

    if not rows:
        return None

    row = rows[0]
    return ClientRecord(id=row[0], name=row[1], document_number=row[2], email=row[3])
