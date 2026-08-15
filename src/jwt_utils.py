"""Emissão e validação de JWT — compatível com `app/shared/security.py`
do repositório `oficina-mecanica-fiap`.

Usa `PyJWT` em vez de `python-jose` (usado pela aplicação principal) só
porque é uma dependência mais leve para empacotar num Lambda; para tokens
HS256 os dois são intercambiáveis — o token gerado aqui é assinado com o
mesmo segredo (`JWT_SECRET_KEY`, lido do secret da aplicação principal) e
tem exatamente o mesmo formato de claims (`sub` + `exp`) que
`create_access_token` no repositório principal, então
`decode_access_token` (jose) valida sem alterações.

Claim extra: `type: "client"`, para a aplicação principal poder diferenciar
no futuro um token de cliente (emitido aqui, a partir do CPF) de um token de
administrador (emitido por `POST /auth/token`, `sub` = username) — ver
ADR-0004 do repositório principal, que já antecipa essa necessidade.
"""

from datetime import UTC, datetime, timedelta

import jwt


def create_client_token(
    *,
    document_number: str,
    client_id: int,
    secret_key: str,
    algorithm: str,
    expire_minutes: int,
) -> str:
    now = datetime.now(UTC)
    payload = {
        "sub": document_number,
        "type": "client",
        "client_id": client_id,
        "iat": now,
        "exp": now + timedelta(minutes=expire_minutes),
    }
    return jwt.encode(payload, secret_key, algorithm=algorithm)


def decode_token(token: str, *, secret_key: str, algorithm: str) -> dict[str, object]:
    return jwt.decode(token, secret_key, algorithms=[algorithm])
