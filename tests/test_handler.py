import json
from types import SimpleNamespace

import pytest

import handler
from db import ClientRecord

VALID_CPF = "529.982.247-25"
DOCUMENT_NUMBER = "52998224725"
JWT_SECRET = "test-jwt-secret"  # mesmo valor setado por tests/conftest.py


class FakeContext(SimpleNamespace):
    aws_request_id = "test-request-id"


@pytest.fixture
def fake_context():
    return FakeContext()


def _event_with_body(body: dict) -> dict:
    return {"body": json.dumps(body)}


def test_authenticate_handler_returns_token_for_existing_client(monkeypatch, fake_context):
    monkeypatch.setattr(
        handler,
        "find_client_by_document",
        lambda db, document_number: ClientRecord(
            id=7, name="Cliente Teste", document_number=document_number, email="cliente@example.com"
        ),
    )

    response = handler.authenticate_handler(_event_with_body({"cpf": VALID_CPF}), fake_context)

    assert response["statusCode"] == 200
    body = json.loads(response["body"])
    assert body["token_type"] == "bearer"

    from jwt_utils import decode_token

    claims = decode_token(body["access_token"], secret_key=JWT_SECRET, algorithm="HS256")
    assert claims["sub"] == DOCUMENT_NUMBER
    assert claims["client_id"] == 7
    assert claims["type"] == "client"


def test_authenticate_handler_returns_404_for_unknown_client(monkeypatch, fake_context):
    monkeypatch.setattr(handler, "find_client_by_document", lambda db, document_number: None)

    response = handler.authenticate_handler(_event_with_body({"cpf": VALID_CPF}), fake_context)

    assert response["statusCode"] == 404


def test_authenticate_handler_returns_400_for_invalid_cpf(fake_context):
    response = handler.authenticate_handler(_event_with_body({"cpf": "123"}), fake_context)

    assert response["statusCode"] == 400


def test_authenticate_handler_returns_400_for_malformed_json(fake_context):
    response = handler.authenticate_handler({"body": "not-json"}, fake_context)

    assert response["statusCode"] == 400


def test_authenticate_handler_returns_400_when_body_missing(fake_context):
    response = handler.authenticate_handler({}, fake_context)

    assert response["statusCode"] == 400


def test_authorizer_handler_grants_access_for_valid_token(fake_context):
    from jwt_utils import create_client_token

    token = create_client_token(
        document_number=DOCUMENT_NUMBER, client_id=7, secret_key=JWT_SECRET, algorithm="HS256", expire_minutes=30
    )

    event = {"headers": {"Authorization": f"Bearer {token}"}}
    response = handler.authorizer_handler(event, fake_context)

    assert response["isAuthorized"] is True
    assert response["context"]["sub"] == DOCUMENT_NUMBER
    assert response["context"]["client_id"] == "7"


def test_authorizer_handler_denies_missing_header(fake_context):
    response = handler.authorizer_handler({"headers": {}}, fake_context)

    assert response["isAuthorized"] is False


def test_authorizer_handler_denies_invalid_token(fake_context):
    event = {"headers": {"authorization": "Bearer not-a-real-token"}}
    response = handler.authorizer_handler(event, fake_context)

    assert response["isAuthorized"] is False
