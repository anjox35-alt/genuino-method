"""Varredura de segredo e de caminho pessoal.

Separado de `gates.py` porque e o gate com a maior superficie de regra: cada
padrao aqui existe por um vazamento plausivel, e a lista cresce com o tempo.

Caminho pessoal conta como achado porque este metodo publica em repositorio
publico -- a pasta de usuario identifica a pessoa tao bem quanto um token.
"""

from __future__ import annotations

import re
from collections.abc import Sequence
from pathlib import Path

from .core import FAIL, PASS, Finding, GateResult, iter_text_files, read_lines

# Cada regra existe por um vazamento plausivel e concreto. Regra generica demais
# gera ruido, e um gate ruidoso e desligado pelo time -- que e a pior falha.
SECRET_RULES: Sequence[tuple[str, re.Pattern[str]]] = (
    ("github-token", re.compile(r"\bgh[pousr]_[A-Za-z0-9]{16,}")),
    ("github-pat-fine", re.compile(r"\bgithub_pat_[A-Za-z0-9_]{20,}")),
    ("openai-key", re.compile(r"\bsk-[A-Za-z0-9_-]{20,}")),
    ("anthropic-key", re.compile(r"\bsk-ant-[A-Za-z0-9_-]{20,}")),
    ("aws-access-key", re.compile(r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b")),
    ("slack-token", re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{10,}")),
    ("google-api-key", re.compile(r"\bAIza[0-9A-Za-z_-]{35}\b")),
    ("private-key-block", re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH |PGP )?PRIVATE KEY-----")),
    ("windows-user-path", re.compile(r"[A-Za-z]:\\\\?Users\\\\?[A-Za-z0-9._-]+", re.IGNORECASE)),
    ("unix-home-path", re.compile(r"/(?:home|Users)/(?!runner\b)[A-Za-z0-9._-]+/")),
)

# Um placeholder nao e um segredo. Sem esta lista, o gate reprova a propria
# documentacao e ensina o time a ignora-lo.
PLACEHOLDER_HINTS = (
    "example",
    "placeholder",
    "your-",
    "xxxx",
    "<token>",
    "dummy",
    "fake",
    "redacted",
    "changeme",
    "sample",
)


# Marcador explicito para o unico caso legitimo de um segredo-formato aparecer
# em arquivo versionado: a fixture que prova que este gate reprova.
#
# A alternativa seria isentar o diretorio de testes inteiro. Isso abriria um
# ponto cego permanente: um segredo real vazado para dentro de tests/ passaria
# sem ser visto. O marcador exige que quem escreveu a linha tenha declarado a
# intencao naquela linha, e deixa a isencao auditavel por grep.
FIXTURE_MARKER = "genuino:fixture"


def _looks_like_placeholder(excerpt: str) -> bool:
    low = excerpt.lower()
    return any(hint in low for hint in PLACEHOLDER_HINTS)


def _is_declared_fixture(lines: list[str], index: int) -> bool:
    """Verdadeiro se a linha, ou a imediatamente anterior, carrega o marcador.

    Aceitar a linha anterior permite marcar um bloco de texto multilinha sem
    poluir o proprio literal.
    """
    if FIXTURE_MARKER in lines[index]:
        return True
    return index > 0 and FIXTURE_MARKER in lines[index - 1]


def scan_secrets(root: Path, allow_paths: Sequence[str] = ()) -> GateResult:
    """Procura segredo e caminho pessoal em arquivos versionaveis.

    Caminho pessoal entra aqui porque este metodo publica em repositorio
    publico: `C:\\Users\\<nome>` identifica a pessoa tao bem quanto um token.
    """
    findings: list[Finding] = []
    allowed = tuple(allow_paths)

    for path in iter_text_files(root):
        rel = path.relative_to(root).as_posix()
        if any(rel.startswith(a) for a in allowed):
            continue
        lines = read_lines(path)
        for index, line in enumerate(lines):
            if _is_declared_fixture(lines, index):
                continue
            for rule, pattern in SECRET_RULES:
                if not pattern.search(line):
                    continue
                excerpt = line.strip()[:200]
                if _looks_like_placeholder(excerpt):
                    continue
                findings.append(
                    Finding(path=rel, line=index + 1, rule=rule, excerpt=excerpt)
                )

    if findings:
        return GateResult(
            status=FAIL,
            summary=f"{len(findings)} ocorrencia(s) de segredo ou caminho pessoal.",
            findings=findings,
        )
    return GateResult(
        status=PASS,
        summary="Nenhum segredo ou caminho pessoal encontrado.",
        limits=[
            "Cobre apenas os padroes declarados em SECRET_RULES.",
            "Ausencia de achado nao prova ausencia de segredo.",
        ],
    )


