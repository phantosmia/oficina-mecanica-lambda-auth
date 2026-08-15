"""Entrypoints da Lambda de autenticação via CPF.

Dois handlers, mapeados a dois usos distintos do AWS API Gateway (ver
`terraform/main.tf` e RFC-0004 / ADR-0004 do repositório principal):

- `authenticate_handler`: integração da rota `POST /auth/cpf` — valida o
  CPF, consulta a existência do cliente no banco (RDS, dentro da VPC do
  banco de dados) e devolve um JWT.
- `authorizer_handler`: Lambda Authorizer (formato "simple responses" do
  HTTP API) usado pelas demais rotas protegidas, validando o JWT emitido
  acima antes de a requisição ser encaminhada ao cluster EKS. Não faz
  nenhuma chamada de rede (nem RDS, nem Secrets Manager em tempo de
  execução — o segredo já chega via variável de ambiente, ver `settings.py`),
  por isso não precisa rodar dentro de uma VPC.
"""

import json
import logging
from typing import Any

import jwt as pyjwt

from cpf import InvalidCpfError, validate_cpf
from db import find_client_by_document
from jwt_utils import create_client_token, decode_token
from settings import load_db_settings, load_jwt_settings

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def _response(status_code: int, body: dict[str, Any]) -> dict[str, Any]:
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }


def authenticate_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    request_id = getattr(context, "aws_request_id", None)
    logger.info(json.dumps({"event": "auth_request_received", "request_id": request_id}))

    try:
        payload = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return _response(400, {"detail": "Corpo da requisição precisa ser um JSON válido."})

    cpf_input = payload.get("cpf", "")

    try:
        document_number = validate_cpf(cpf_input)
    except InvalidCpfError as error:
        logger.info(json.dumps({"event": "auth_invalid_cpf", "request_id": request_id}))
        return _response(400, {"detail": str(error)})

    db_settings = load_db_settings()
    client = find_client_by_document(db_settings, document_number)
    # Cliente inexistente e cliente inativo recebem a mesma resposta, de
    # propósito: não revelar a quem não se autenticou se um CPF pertence a
    # um cliente inativo ou simplesmente não existe (ver docs/regras-negocio.md
    # do repositório principal).
    if client is None or not client.is_active:
        logger.info(json.dumps({"event": "auth_client_not_found_or_inactive", "request_id": request_id}))
        return _response(404, {"detail": "Cliente não encontrado ou inativo para este CPF."})

    jwt_settings = load_jwt_settings()
    token = create_client_token(
        document_number=client.document_number,
        client_id=client.id,
        secret_key=jwt_settings.secret_key,
        algorithm=jwt_settings.algorithm,
        expire_minutes=jwt_settings.access_token_expire_minutes,
    )

    logger.info(
        json.dumps({"event": "auth_token_issued", "request_id": request_id, "client_id": client.id})
    )
    return _response(200, {"access_token": token, "token_type": "bearer"})


def authorizer_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """Lambda Authorizer (REQUEST, payload simples do API Gateway HTTP API)."""
    request_id = getattr(context, "aws_request_id", None)
    headers = {key.lower(): value for key, value in (event.get("headers") or {}).items()}
    authorization = headers.get("authorization", "")

    if not authorization.lower().startswith("bearer "):
        logger.info(json.dumps({"event": "authz_missing_token", "request_id": request_id}))
        return {"isAuthorized": False}

    token = authorization[len("bearer "):].strip()
    jwt_settings = load_jwt_settings()

    try:
        claims = decode_token(token, secret_key=jwt_settings.secret_key, algorithm=jwt_settings.algorithm)
    except pyjwt.PyJWTError:
        logger.info(json.dumps({"event": "authz_invalid_token", "request_id": request_id}))
        return {"isAuthorized": False}

    logger.info(json.dumps({"event": "authz_granted", "request_id": request_id, "sub": claims.get("sub")}))
    return {
        "isAuthorized": True,
        "context": {
            "sub": str(claims.get("sub", "")),
            "type": str(claims.get("type", "")),
            "client_id": str(claims.get("client_id", "")),
        },
    }
