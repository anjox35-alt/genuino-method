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
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path

from .core import (
    BINARY_SUFFIXES,
    FAIL,
    IGNORED_DIRS,
    INDETERMINADO,
    PASS,
    Finding,
    GateResult,
    iter_text_files,
    read_lines,
)
from .secrets import FIXTURE_MARKER, PLACEHOLDER_HINTS, SECRET_RULES, scan_secrets

__all__ = [
    "BINARY_SUFFIXES",
    "FAIL",
    "INDETERMINADO",
    "IGNORED_DIRS",
    "PASS",
    "Finding",
    "GateResult",
    "iter_text_files",
    "read_lines",
    "FIXTURE_MARKER",
    "PLACEHOLDER_HINTS",
    "SECRET_RULES",
    "scan_secrets",
    "BloatThresholds",
    "check_bloat",
    "scan_security",
    "selftest_security",
    "validate_skill",
]


# --------------------------------------------------------------------------
# scan_security
# --------------------------------------------------------------------------


# Regras vendorizadas, versionadas junto com o codigo.
#
# `--config auto` baixa o ruleset do servidor a cada execucao, e o semgrep
# recusa essa combinacao com `--metrics=off`: "Cannot create auto config when
# metrics are off". O gate ficava permanentemente INDETERMINADO -- honesto, mas
# inutil.
#
# Vendorizar resolve os dois problemas de uma vez. Um gate cujo conteudo chega
# da rede em tempo de execucao nao e reproduzivel: a mesma arvore passa hoje e
# reprova amanha sem que uma linha mude. E `--metrics=off` deixa de conflitar,
# porque nao ha config remota a resolver.
VENDORED_RULES = ".semgrep/rules"


def scan_security(root: Path, config: str | None = None, timeout: int = 300) -> GateResult:
    """Delega ao semgrep local, com regras vendorizadas no repositorio.

    Sem semgrep, ou sem regras, o veredito e INDETERMINADO -- nunca PASS.
    """
    binary = shutil.which("semgrep")
    if binary is None:
        return GateResult(
            status=INDETERMINADO,
            summary="semgrep nao encontrado no PATH. Nao foi possivel medir.",
            limits=["Instale semgrep para que este gate produza veredito."],
        )

    if config is None:
        vendored = root / VENDORED_RULES
        if not vendored.is_dir():
            return GateResult(
                status=INDETERMINADO,
                summary=(
                    f"Regras vendorizadas ausentes em {VENDORED_RULES}. Nao foi possivel medir."
                ),
                limits=[
                    "Ausencia de regras nao e ausencia de vulnerabilidade.",
                    f"Vendorize um ruleset em {VENDORED_RULES} e declare a procedencia.",
                ],
            )
        config = str(vendored)

    # `.semgrep/` sai do escaneamento por duas razoes distintas:
    #
    #  - `rules/` contem os PADROES de deteccao. Escanear a regra que procura
    #    "chave PGP" faz o semgrep encontrar a propria regra e reportar como
    #    achado. Ruido garantido, em todo run.
    #  - `selftest/insecure.ts` e vulneravel DE PROPOSITO: ele existe para provar
    #    que o gate reprova. Contar isso como achado do projeto seria confundir
    #    o teste do gate com um defeito do produto.
    #
    # O selftest continua sendo verificado -- por `selftest_security`, que roda
    # justamente sobre ele e exige a reprovacao.
    return _run_semgrep(binary, config, root, timeout, exclude=".semgrep")


def _run_semgrep(
    binary: str,
    config: str,
    target: Path,
    timeout: int,
    exclude: str | None,
) -> GateResult:
    """Executa o semgrep sobre um alvo e traduz a saida para o contrato."""
    cmd = [binary, "--config", config, "--json", "--quiet", "--metrics=off"]
    if exclude:
        cmd += ["--exclude", exclude]
    cmd.append(str(target))

    try:
        proc = subprocess.run(  # noqa: S603 - binario resolvido via which
            cmd, capture_output=True, text=True, timeout=timeout, check=False
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


def selftest_security(root: Path, timeout: int = 300) -> GateResult:
    """Prova que o gate de seguranca ainda reprova o que deve reprovar.

    Um gate que so foi visto aprovando nao foi testado -- foi acompanhado. Este
    selftest roda o mesmo semgrep, com as mesmas regras, sobre dois arquivos de
    controle:

        .semgrep/selftest/insecure.*   precisa REPROVAR
        .semgrep/selftest/secure.*     precisa PASSAR

    Se o ruleset for esvaziado, corrompido ou substituido por um que nao detecta
    nada, o scan normal continuaria devolvendo PASS em silencio. Este selftest e
    o que impede esse PASS de ser lido como seguranca.
    """
    selftest_dir = root / ".semgrep" / "selftest"
    if not selftest_dir.is_dir():
        return GateResult(
            status=INDETERMINADO,
            summary="Diretorio de selftest ausente. O gate de seguranca nao foi verificado.",
        )

    insecure = sorted(selftest_dir.glob("insecure.*"))
    secure = sorted(selftest_dir.glob("secure.*"))
    if not insecure or not secure:
        return GateResult(
            status=INDETERMINADO,
            summary="Selftest precisa de um arquivo 'insecure.*' e um 'secure.*'.",
        )

    # Aponta o semgrep DIRETO para o diretorio de selftest.
    #
    # Nao da para reaproveitar `scan_security` aqui: ele exclui `.semgrep/`, que
    # e justamente onde o selftest vive. Chamar o scan normal faria o selftest
    # medir uma arvore da qual ele proprio foi removido, e reportar "o ruleset
    # nao detecta nada" -- um falso alarme causado pela propria exclusao.
    ruim = _run_semgrep(
        binary=shutil.which("semgrep") or "semgrep",
        config=str(root / VENDORED_RULES),
        target=selftest_dir,
        timeout=timeout,
        exclude=None,
    )
    if ruim.status == INDETERMINADO:
        return GateResult(
            status=INDETERMINADO,
            summary=f"Nao foi possivel rodar o selftest: {ruim.summary}",
        )

    achados_insecure = [f for f in ruim.findings if "insecure" in f.path]
    achados_secure = [f for f in ruim.findings if "insecure" not in f.path]

    problemas: list[str] = []
    if not achados_insecure:
        problemas.append("o arquivo inseguro NAO foi reprovado: o ruleset nao esta detectando")
    if achados_secure:
        problemas.append(
            f"o arquivo seguro foi reprovado: {len(achados_secure)} falso(s) positivo(s)"
        )

    if problemas:
        return GateResult(
            status=FAIL,
            summary="Selftest de seguranca reprovou: " + "; ".join(problemas),
            findings=achados_insecure + achados_secure,
        )

    return GateResult(
        status=PASS,
        summary=(
            f"Selftest de seguranca OK: o arquivo inseguro produziu "
            f"{len(achados_insecure)} achado(s) e o seguro, nenhum."
        ),
        limits=["Prova que o ruleset detecta os casos de controle, nao que cobre tudo."],
    )


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
        lines = read_lines(path)

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

    # O sumario nomeia as extensoes medidas porque "18 arquivos" sozinho se le
    # como "o repositorio". Um markdown de 606 KB ja passou ao lado deste gate
    # enquanto ele reportava PASS -- corretamente, pois markdown nunca esteve no
    # escopo. O defeito estava no relato, que deixava o leitor concluir mais do
    # que fora medido.
    escopo = " ".join(sorted(suffixes))
    alcance = f"{len(files)} arquivo(s) de codigo ({escopo})"
    limites = [
        "Mede tamanho e repeticao, nao corretude nem necessidade.",
        f"Fora do escopo, nao medido: qualquer arquivo que nao termine em {escopo}.",
    ]

    if findings:
        return GateResult(
            status=FAIL,
            summary=f"{len(findings)} sintoma(s) de inflacao em {alcance}.",
            findings=findings,
            limits=limites,
        )
    return GateResult(
        status=PASS,
        summary=f"Nenhum sintoma de inflacao em {alcance}.",
        limits=limites,
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


def _function_end(lines: list[str], start: int) -> int:
    """Acha onde a funcao iniciada em `start` termina.

    Duas estrategias, porque as linguagens do projeto delimitam bloco de formas
    diferentes:

    - Chaves (PowerShell, JS, TS): conta abre e fecha ate balancear.
    - Indentacao (Python): termina na primeira linha nao vazia cuja indentacao
      volta ao nivel da declaracao ou acima.

    A versao anterior usava "ate a proxima funcao", e isso produzia falso
    positivo grosseiro: a ultima funcao de um arquivo engolia todo o codigo
    top-level abaixo dela. Uma funcao de oito linhas era reportada com cento e
    oitenta. Gate que acusa o inocente perde a autoridade de acusar o culpado.
    """
    header = lines[start]

    if "{" in header:
        depth = 0
        for index in range(start, len(lines)):
            depth += lines[index].count("{") - lines[index].count("}")
            if depth <= 0 and index > start:
                return index + 1
            if depth == 0 and index == start and "}" in lines[index]:
                return index + 1
        return len(lines)

    base_indent = len(header) - len(header.lstrip())
    for index in range(start + 1, len(lines)):
        line = lines[index]
        if not line.strip():
            continue
        if len(line) - len(line.lstrip()) <= base_indent:
            return index
    return len(lines)


def _find_long_functions(rel: str, lines: list[str], max_lines: int) -> list[Finding]:
    """Aponta funcoes que passaram do teto de linhas.

    E heuristica, nao parser. Serve para apontar o candidato a revisao, nao para
    julgar o codigo.
    """
    out: list[Finding] = []
    for start, header in enumerate(lines):
        if not _FUNC_START.match(header):
            continue
        length = _function_end(lines, start) - start
        if length > max_lines:
            out.append(
                Finding(
                    path=rel,
                    line=start + 1,
                    rule="funcao-longa",
                    excerpt=f"~{length} linhas (teto {max_lines}): {header.strip()[:120]}",
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
