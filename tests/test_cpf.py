import pytest

from cpf import InvalidCpfError, validate_cpf


@pytest.mark.parametrize(
    "raw",
    [
        "529.982.247-25",
        "52998224725",
        "  529.982.247-25  ",
    ],
)
def test_validate_cpf_accepts_valid_document_in_any_format(raw):
    assert validate_cpf(raw) == "52998224725"


def test_validate_cpf_returns_digits_only():
    assert validate_cpf("111.444.777-35") == "11144477735"


@pytest.mark.parametrize(
    "raw",
    [
        "",
        "123",
        "111.111.111-11",
        "000.000.000-00",
        "529.982.247-24",
        "not-a-cpf",
    ],
)
def test_validate_cpf_rejects_invalid_document(raw):
    with pytest.raises(InvalidCpfError):
        validate_cpf(raw)
