"""Tipos e utilitarios compartilhados pelos gates.

Existe para quebrar a dependencia circular entre `gates` e `secrets`: os dois
precisam de `Finding`, `GateResult` e da listagem de arquivos, e nenhum dos dois
pode importar o outro.
"""

from __future__ import annotations

import subprocess
from collections.abc import Iterable
from dataclasses import dataclass, field
from pathlib import Path

PASS = "PASS"
FAIL = "FAIL"
INDETERMINADO = "INDETERMINADO"

# Diretorios que nunca sao varridos: sao gerados, nao autorais.
IGNORED_DIRS = frozenset(
    {
        ".git",
        "node_modules",
        ".venv",
        "venv",
        "__pycache__",
        ".pytest_cache",
        ".ruff_cache",
        "dist",
        "build",
        ".mypy_cache",
    }
)

# Extensoes binarias: varrer bytes por regex de texto produz ruido, nao achado.
BINARY_SUFFIXES = frozenset(
    {
        ".png", ".jpg", ".jpeg", ".gif", ".ico", ".webp", ".svg",
        ".zip", ".gz", ".tar", ".7z", ".rar",
        ".pdf", ".woff", ".woff2", ".ttf", ".otf", ".eot",
        ".exe", ".dll", ".so", ".dylib", ".pyc", ".class", ".jar",
        ".mp4", ".mp3", ".wav", ".avi", ".mov",
    }
)


@dataclass
class Finding:
    """Uma ocorrencia concreta, ancorada em arquivo e linha."""

    path: str
    line: int
    rule: str
    excerpt: str


@dataclass
class GateResult:
    """Veredito de um gate, com a evidencia que o sustenta."""

    status: str
    summary: str
    findings: list[Finding] = field(default_factory=list)
    limits: list[str] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "status": self.status,
            "summary": self.summary,
            "findings": [
                {
                    "path": f.path,
                    "line": f.line,
                    "rule": f.rule,
                    "excerpt": f.excerpt,
                }
                for f in self.findings
            ],
            "limits": self.limits,
        }


def _git_tracked_files(root: Path) -> list[Path] | None:
    """Arquivos que o git publicaria: versionados mais novos nao ignorados.

    Sem isto o gate varre o que o `.gitignore` ja exclui -- logs de execucao,
    artefatos de build, evidencia local -- e reprova por conteudo que nunca sai
    da maquina. Um gate que reprova o que nao vai ser publicado ensina o time a
    ignora-lo.

    Devolve None quando `root` nao e um repositorio git, para o chamador cair no
    percurso simples do sistema de arquivos.
    """
    try:
        proc = subprocess.run(  # noqa: S603 - argumentos fixos
            ["git", "-C", str(root), "ls-files", "--cached", "--others", "--exclude-standard"],
            capture_output=True,
            text=True,
            timeout=60,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None

    if proc.returncode != 0:
        return None

    return [
        root / line.strip()
        for line in proc.stdout.splitlines()
        if line.strip()
    ]


def iter_text_files(root: Path, extra_ignores: Iterable[str] = ()) -> list[Path]:
    """Lista arquivos de texto sob `root`, pulando gerados e ignorados pelo git."""
    ignored = IGNORED_DIRS | set(extra_ignores)
    if not root.exists():
        return []

    candidates = _git_tracked_files(root)
    if candidates is None:
        candidates = [p for p in root.rglob("*")]

    out: list[Path] = []
    for path in candidates:
        if not path.is_file():
            continue
        if any(part in ignored for part in path.relative_to(root).parts):
            continue
        if path.suffix.lower() in BINARY_SUFFIXES:
            continue
        out.append(path)
    return out


def read_lines(path: Path) -> list[str]:
    try:
        return path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return []


