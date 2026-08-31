"""Gates de verificacao do metodo Genuino.

Logica pura, sem dependencia do protocolo MCP. Cada gate devolve um `GateResult`
e nunca converte ausencia de evidencia em aprovacao: quando a ferramenta
subjacente nao esta disponivel, o veredito e INDETERMINADO, nao PASS.

O contrato de tres faixas herdado de `green-loop.sh` vale aqui:
    PASS          -> passou
    FAIL          -> reprovacao medida
    INDETERMINADO -> nao foi possivel medir; e falha de ambiente, nao do codigo
"""

from __future__ import annotations

import json
import re
import shutil
import subprocess
from collections.abc import Iterable, Sequence
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


def iter_text_files(root: Path, extra_ignores: Iterable[str] = ()) -> list[Path]:
    """Lista arquivos de texto sob `root`, pulando diretorios gerados."""
    ignored = IGNORED_DIRS | set(extra_ignores)
    out: list[Path] = []
    if not root.exists():
        return out
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        if any(part in ignored for part in path.relative_to(root).parts):
            continue
        if path.suffix.lower() in BINARY_SUFFIXES:
            continue
        out.append(path)
    return out


def _read_lines(path: Path) -> list[str]:
    try:
        return path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return []


# --------------------------------------------------------------------------
# scan_secrets
# --------------------------------------------------------------------------

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
        lines = _read_lines(path)
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


# --------------------------------------------------------------------------
# scan_security
# --------------------------------------------------------------------------


def scan_security(root: Path, config: str = "auto", timeout: int = 300) -> GateResult:
    """Delega ao semgrep local. Sem semgrep, o veredito e INDETERMINADO."""
    binary = shutil.which("semgrep")
    if binary is None:
        return GateResult(
            status=INDETERMINADO,
            summary="semgrep nao encontrado no PATH. Nao foi possivel medir.",
            limits=["Instale semgrep para que este gate produza veredito."],
        )

    try:
        proc = subprocess.run(  # noqa: S603 - binario resolvido via which
            [binary, "--config", config, "--json", "--quiet", "--metrics=off", str(root)],
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired:
        return GateResult(
            status=INDETERMINADO,
            summary=f"semgrep excedeu {timeout}s. Nao foi possivel medir.",
        )
    except OSError as exc:
        return GateResult(
            status=INDETERMINADO,
            summary=f"Falha ao executar semgrep: {exc}",
        )

    return _interpret_semgrep(proc, config)


def _interpret_semgrep(proc: subprocess.CompletedProcess[str], config: str) -> GateResult:
    """Traduz a saida do semgrep para o contrato de tres faixas.

    Exit 0 = sem achado, 1 = achados, >=2 = erro do proprio semgrep. Colapsar 1 e
    2 transformaria erro de ferramenta em aprovacao silenciosa.
    """
    if proc.returncode >= 2:
        return GateResult(
            status=INDETERMINADO,
            summary=f"semgrep retornou {proc.returncode}. Nao foi possivel medir.",
            limits=[proc.stderr.strip()[:500]] if proc.stderr else [],
        )

    try:
        payload = json.loads(proc.stdout or "{}")
    except json.JSONDecodeError:
        return GateResult(
            status=INDETERMINADO,
            summary="Saida do semgrep nao e JSON valido. Nao foi possivel medir.",
        )

    findings = [
        Finding(
            path=str(r.get("path", "?")),
            line=int(r.get("start", {}).get("line", 0)),
            rule=str(r.get("check_id", "?")),
            excerpt=str(r.get("extra", {}).get("message", ""))[:200],
        )
        for r in payload.get("results", [])
    ]

    if findings:
        return GateResult(
            status=FAIL,
            summary=f"semgrep apontou {len(findings)} achado(s).",
            findings=findings,
        )
    return GateResult(
        status=PASS,
        summary="semgrep nao apontou achados.",
        limits=[f"Cobertura limitada ao config '{config}'."],
    )


# --------------------------------------------------------------------------
# check_bloat
# --------------------------------------------------------------------------


@dataclass
class BloatThresholds:
    """Tetos de inflacao. Cada um existe por um sintoma observavel."""

    max_file_lines: int = 600
    max_function_lines: int = 80
    max_duplicate_block_lines: int = 12
    min_duplicate_occurrences: int = 3


def check_bloat(
    root: Path,
    thresholds: BloatThresholds | None = None,
    suffixes: Sequence[str] = (".py", ".ts", ".js", ".mjs", ".ps1"),
    skip_paths: Sequence[str] = (),
) -> GateResult:
    """Mede inflacao: arquivo gigante, funcao gigante e bloco repetido.

    Nao mede 'qualidade'. Mede tres sintomas contaveis de codigo que cresceu sem
    ser lido de novo.

    `skip_paths` isenta prefixos relativos. Serve para conteudo importado e
    selado, que e governado pelo manifesto de hash e nao pode ser refatorado sem
    quebrar o selo -- medir estilo ali produziria um achado sobre o qual ninguem
    pode agir.
    """
    th = thresholds or BloatThresholds()
    findings: list[Finding] = []
    block_index: dict[str, list[tuple[str, int]]] = {}
    skipped = tuple(skip_paths)

    files = [
        p
        for p in iter_text_files(root)
        if p.suffix.lower() in set(suffixes)
        and not any(p.relative_to(root).as_posix().startswith(s) for s in skipped)
    ]

    for path in files:
        rel = path.relative_to(root).as_posix()
        lines = _read_lines(path)

        if len(lines) > th.max_file_lines:
            findings.append(
                Finding(
                    path=rel,
                    line=len(lines),
                    rule="arquivo-longo",
                    excerpt=f"{len(lines)} linhas (teto {th.max_file_lines}).",
                )
            )

        findings.extend(_find_long_functions(rel, lines, th.max_function_lines))
        _index_blocks(block_index, rel, lines, th.max_duplicate_block_lines)

    findings.extend(_report_duplicates(block_index, th))

    if findings:
        return GateResult(
            status=FAIL,
            summary=f"{len(findings)} sintoma(s) de inflacao em {len(files)} arquivo(s).",
            findings=findings,
        )
    return GateResult(
        status=PASS,
        summary=f"Nenhum sintoma de inflacao em {len(files)} arquivo(s).",
        limits=["Mede tamanho e repeticao, nao corretude nem necessidade."],
    )


def _index_blocks(
    index: dict[str, list[tuple[str, int]]],
    rel: str,
    lines: list[str],
    window: int,
) -> None:
    """Indexa janelas de linhas significativas para achar repeticao entre arquivos.

    Comentario e linha vazia sao descartados: dois blocos que so diferem em
    comentario continuam sendo o mesmo codigo duplicado.
    """
    meaningful = [
        (i, ln.strip())
        for i, ln in enumerate(lines, start=1)
        if ln.strip() and not ln.strip().startswith(("#", "//", "*", "<#"))
    ]
    for start in range(len(meaningful) - window + 1):
        chunk = meaningful[start : start + window]
        key = "\n".join(text for _, text in chunk)
        index.setdefault(key, []).append((rel, chunk[0][0]))


def _report_duplicates(
    index: dict[str, list[tuple[str, int]]],
    thresholds: BloatThresholds,
) -> list[Finding]:
    """Converte o indice de blocos em achados, um por bloco repetido demais."""
    findings: list[Finding] = []
    for occurrences in index.values():
        if len(occurrences) < thresholds.min_duplicate_occurrences:
            continue
        rel, line = occurrences[0]
        locations = ", ".join(f"{p}:{ln}" for p, ln in occurrences[:5])
        findings.append(
            Finding(
                path=rel,
                line=line,
                rule="bloco-duplicado",
                excerpt=(
                    f"{len(occurrences)} ocorrencias de bloco identico de "
                    f"{thresholds.max_duplicate_block_lines} linhas: {locations}"
                ),
            )
        )
    return findings


_FUNC_START = re.compile(
    r"^\s*(?:def\s+\w+|async\s+def\s+\w+|function\s+\w+|export\s+function\s+\w+"
    r"|function\s+[A-Z][\w-]*|\w+\s*=\s*(?:async\s*)?\([^)]*\)\s*=>)"
)


def _find_long_functions(rel: str, lines: list[str], max_lines: int) -> list[Finding]:
    """Aproxima o tamanho de funcao por indentacao e por chave de bloco.

    E heuristica, nao parser. Serve para apontar o candidato, nao para julgar.
    """
    out: list[Finding] = []
    starts = [i for i, ln in enumerate(lines) if _FUNC_START.match(ln)]
    for pos, start in enumerate(starts):
        end = starts[pos + 1] if pos + 1 < len(starts) else len(lines)
        length = end - start
        if length > max_lines:
            out.append(
                Finding(
                    path=rel,
                    line=start + 1,
                    rule="funcao-longa",
                    excerpt=f"~{length} linhas (teto {max_lines}): {lines[start].strip()[:120]}",
                )
            )
    return out


# --------------------------------------------------------------------------
# validate_skill
# --------------------------------------------------------------------------

_KEBAB = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")

# Indicadores de bloco escalar YAML, com os modificadores de chomping.
_BLOCK_SCALAR = re.compile(r"^[|>][+-]?\d*$")


def _parse_frontmatter(raw: str) -> tuple[dict[str, str], list[tuple[int, str]]]:
    """Le o frontmatter aceitando bloco escalar YAML.

    Uma `description:` longa e quase sempre escrita como `description: >` com as
    linhas seguintes indentadas. Tratar cada uma dessas linhas como um campo
    malformado faz o gate reprovar um arquivo perfeitamente valido -- e um gate
    que reprova conteudo bom acaba desligado, que e a pior falha possivel.

    Retorna os campos e a lista de linhas realmente malformadas.
    """
    fields: dict[str, str] = {}
    malformed: list[tuple[int, str]] = []
    continuation: list[str] = []
    current: str | None = None

    def flush() -> None:
        if current is not None and continuation:
            fields[current] = (fields.get(current, "") + " " + " ".join(continuation)).strip()
        continuation.clear()

    for lineno, line in enumerate(raw.strip().splitlines(), start=2):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue

        indented = line[:1] in (" ", "\t")
        if indented and current is not None:
            # Continuacao do bloco escalar aberto pelo campo anterior.
            continuation.append(stripped)
            continue

        if ":" not in line:
            malformed.append((lineno, stripped))
            continue

        flush()
        key, value = line.split(":", 1)
        key = key.strip()
        value = value.strip()
        current = key
        # `>` ou `|` sozinhos abrem um bloco: o valor real vem nas linhas
        # indentadas seguintes.
        fields[key] = "" if _BLOCK_SCALAR.match(value) else value

    flush()
    return fields, malformed


def validate_skill(path: Path) -> GateResult:
    """Valida um SKILL.md.

    Portado de `guca/genuino-universal-0.1.0/scripts/lib/skills.mjs`, que usa
    allowlist estrita de frontmatter: campo desconhecido e erro, nao aviso.
    """
    if not path.exists():
        return GateResult(
            status=INDETERMINADO,
            summary=f"Arquivo nao encontrado: {path}",
        )

    text = path.read_text(encoding="utf-8", errors="replace")
    rel = path.name
    findings: list[Finding] = []

    if not text.startswith("---"):
        return GateResult(
            status=FAIL,
            summary="SKILL.md nao comeca com frontmatter YAML.",
            findings=[Finding(rel, 1, "frontmatter-ausente", text[:120])],
        )

    parts = text.split("---", 2)
    if len(parts) < 3:
        return GateResult(
            status=FAIL,
            summary="Frontmatter nao esta fechado por '---'.",
            findings=[Finding(rel, 1, "frontmatter-aberto", text[:120])],
        )

    fields, malformed = _parse_frontmatter(parts[1])
    for lineno, text in malformed:
        findings.append(Finding(rel, lineno, "frontmatter-malformado", text[:120]))

    allowed = {"name", "description"}
    for key in fields:
        if key not in allowed:
            findings.append(
                Finding(
                    rel,
                    1,
                    "campo-nao-permitido",
                    f"'{key}' fora da allowlist {sorted(allowed)}",
                )
            )

    name = fields.get("name", "")
    if not name:
        findings.append(Finding(rel, 1, "name-ausente", "frontmatter sem 'name'"))
    elif not _KEBAB.match(name):
        findings.append(Finding(rel, 1, "name-nao-kebab", f"'{name}' nao e kebab-case ASCII"))

    description = fields.get("description", "")
    if not description:
        findings.append(Finding(rel, 1, "description-ausente", "frontmatter sem 'description'"))

    body = parts[2]
    if "TODO" in body:
        for lineno, line in enumerate(body.splitlines(), start=1):
            if "TODO" in line:
                findings.append(Finding(rel, lineno, "todo-no-corpo", line.strip()[:120]))

    if findings:
        return GateResult(
            status=FAIL,
            summary=f"{len(findings)} problema(s) no SKILL.md.",
            findings=findings,
        )
    return GateResult(status=PASS, summary=f"SKILL.md valido: {name}")
