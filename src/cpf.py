"""Validação de CPF, sem dependências externas.

Portado de ``app/shared/validators.py`` do repositório `oficina-mecanica-fiap`
(apenas a parte de CPF — esta Lambda não lida com CNPJ). Mantido como um
módulo isolado, sem import do repositório principal, porque esta função
serverless roda em um runtime próprio e não deve depender do pacote `app`.
"""

CPF_LENGTH = 11


class InvalidCpfError(ValueError):
    """CPF ausente, mal formatado ou com dígitos verificadores inválidos."""


def only_digits(value: str) -> str:
    return "".join(character for character in value if character.isdigit())


def validate_cpf(value: str) -> str:
    """Valida um CPF e retorna apenas os dígitos (sem máscara).

    Levanta ``InvalidCpfError`` se o valor não tiver 11 dígitos, for uma
    sequência repetida (ex.: "000.000.000-00") ou os dígitos verificadores
    não baterem.
    """
    if not value:
        raise InvalidCpfError("CPF é obrigatório.")

    digits = only_digits(value)
    if len(digits) != CPF_LENGTH or digits == digits[0] * CPF_LENGTH:
        raise InvalidCpfError("CPF inválido.")

    first_digit = _cpf_digit(digits[:9])
    second_digit = _cpf_digit(digits[:9] + str(first_digit))
    if not digits.endswith(f"{first_digit}{second_digit}"):
        raise InvalidCpfError("CPF inválido.")

    return digits


def _cpf_digit(value: str) -> int:
    factor = len(value) + 1
    total = sum(int(number) * weight for number, weight in zip(value, range(factor, 1, -1), strict=True))
    remainder = 11 - (total % 11)
    return 0 if remainder >= 10 else remainder
