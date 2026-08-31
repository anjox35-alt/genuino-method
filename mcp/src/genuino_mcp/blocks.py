"""Limites de funcao para o gate de inflacao."""

from __future__ import annotations

import json
import re
import shutil
import subprocess
from pathlib import Path
from typing import Any

from .core import Finding

_FUNC_START = re.compile(
    r"^\s*(?:def\s+\w+|async\s+def\s+\w+|function\s+\w+|export\s+function\s+\w+"
    r"|function\s+[A-Z][\w-]*|\w+\s*=\s*(?:async\s*)?\([^)]*\)\s*=>)"
)
_JS_SUFFIXES = {".js", ".mjs", ".ts"}
# A contagem existente continua para JS/TS; o regex apenas esconde literais
# completos e preserva as quebras de linha para manter os indices alinhados.
_JS_STRING = re.compile(r'"(?:\\[\s\S]|[^"\\])*"|\'(?:\\[\s\S]|[^\'\\])*\'|`(?:\\[\s\S]|[^`\\])*`')
_POWERSHELL_TIMEOUT_SECONDS = 10
_POWERSHELL_FUNCTIONS = """
$ErrorActionPreference = 'Stop'
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    $args[0], [ref]$tokens, [ref]$parseErrors
)
$functions = @(
    $ast.FindAll(
        { param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] },
        $true
    ) | ForEach-Object {
        [pscustomobject]@{ start = $_.Extent.StartLineNumber; end = $_.Extent.EndLineNumber }
    }
)
[pscustomobject]@{ errors = $parseErrors.Count; functions = $functions } |
    ConvertTo-Json -Compress -Depth 3
"""


def find_long_functions(path: Path, rel: str, lines: list[str], max_lines: int) -> list[Finding]:
    """Aponta funcoes que passaram do teto de linhas.

    PowerShell e analisado uma vez por arquivo pelo parser da plataforma. Python
    mantem o fim por indentacao; JS/TS mantem a contagem de chaves, sem contar as
    que pertencem a aspas simples, duplas ou crases.
    """
    starts = [(index, header) for index, header in enumerate(lines) if _FUNC_START.match(header)]
    parser_ends = (
        _powershell_function_ends(path, len(lines))
        if starts and path.suffix.lower() == ".ps1"
        else None
    )
    brace_lines = _brace_lines(path, lines) if parser_ends is None else lines
    out: list[Finding] = []
    for start, header in starts:
        if parser_ends is None:
            end = _function_end(lines, brace_lines, start)
        else:
            end = parser_ends.get(start)
            if end is None:
                continue
        length = end - start
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


def _powershell_function_ends(path: Path, line_count: int) -> dict[int, int] | None:
    """Devolve todos os limites do AST, ou ``None`` para usar o fallback bruto."""
    executable = shutil.which("pwsh")
    if executable is None:
        return None

    command = [
        executable,
        "-NoLogo",
        "-NoProfile",
        "-NonInteractive",
        "-CommandWithArgs",
        _POWERSHELL_FUNCTIONS,
        str(path),
    ]
    try:
        process = subprocess.run(  # noqa: S603 - executavel resolvido via which
            command,
            capture_output=True,
            check=False,
            text=True,
            timeout=_POWERSHELL_TIMEOUT_SECONDS,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None

    if process.returncode != 0:
        return None
    return _decode_powershell_ends(process.stdout, line_count)


def _decode_powershell_ends(output: str, line_count: int) -> dict[int, int] | None:
    try:
        result: Any = json.loads(output.lstrip("\ufeff"))
    except json.JSONDecodeError:
        return None

    errors = result.get("errors") if isinstance(result, dict) else None
    if type(errors) is not int or errors != 0:
        return None
    functions = result.get("functions")
    if not isinstance(functions, list):
        return None

    ends: dict[int, int] = {}
    for function in functions:
        if not isinstance(function, dict):
            return None
        start, end = function.get("start"), function.get("end")
        if type(start) is not int or type(end) is not int or not 1 <= start <= end <= line_count:
            return None
        if start - 1 in ends:
            return None
        ends[start - 1] = end
    return ends


def _brace_lines(path: Path, lines: list[str]) -> list[str]:
    """Mantem a contagem existente, sem deixar literais JS/TS exporem chaves."""
    if path.suffix.lower() not in _JS_SUFFIXES:
        return lines
    source = "\n".join(lines)
    without_strings = _JS_STRING.sub(lambda match: "\n" * match.group().count("\n"), source)
    return without_strings.split("\n")


def _function_end(lines: list[str], brace_lines: list[str], start: int) -> int:
    """Acha o fim pelo fallback de chaves, ou por indentacao para Python.

    O AST do PowerShell e resolvido antes desta funcao, uma vez para todo o
    arquivo. Aqui, PowerShell so chega quando o interpretador ou sua analise nao
    estao disponiveis; JS/TS continua delimitado por chaves e Python por
    indentacao.

    A versao anterior usava "ate a proxima funcao", e isso produzia falso
    positivo grosseiro: a ultima funcao de um arquivo engolia todo o codigo
    top-level abaixo dela. Uma funcao de oito linhas era reportada com cento e
    oitenta. Gate que acusa o inocente perde a autoridade de acusar o culpado.
    """
    if "{" in brace_lines[start]:
        depth = 0
        for index in range(start, len(lines)):
            depth += brace_lines[index].count("{") - brace_lines[index].count("}")
            if depth <= 0 and index > start:
                return index + 1
            if depth == 0 and index == start and "}" in brace_lines[index]:
                return index + 1
        return len(lines)

    base_indent = len(lines[start]) - len(lines[start].lstrip())
    for index in range(start + 1, len(lines)):
        line = lines[index]
        if not line.strip():
            continue
        if len(line) - len(line.lstrip()) <= base_indent:
            return index
    return len(lines)
