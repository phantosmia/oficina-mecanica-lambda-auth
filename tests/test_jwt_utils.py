import pytest

from jwt_utils import create_client_token, decode_token

SECRET = "test-secret"


def test_create_client_token_roundtrip():
    token = create_client_token(
        document_number="52998224725",
        client_id=42,
        secret_key=SECRET,
        algorithm="HS256",
        expire_minutes=30,
    )

    claims = decode_token(token, secret_key=SECRET, algorithm="HS256")

    assert claims["sub"] == "52998224725"
    assert claims["type"] == "client"
    assert claims["client_id"] == 42


def test_decode_token_fails_with_wrong_secret():
    import jwt as pyjwt

    token = create_client_token(
        document_number="52998224725",
        client_id=42,
        secret_key=SECRET,
        algorithm="HS256",
        expire_minutes=30,
    )

    with pytest.raises(pyjwt.PyJWTError):
        decode_token(token, secret_key="wrong-secret", algorithm="HS256")
