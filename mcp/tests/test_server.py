"""Testes de integracao do servidor MCP.

Testar as funcoes de `gates` nao prova que o servidor sobe. Estes testes falam o
protocolo de verdade, contra a instancia real de `MCPServer`.
"""

from __future__ import annotations

import asyncio
import json
from pathlib import Path
from typing import Any

from mcp import Client

from genuino_mcp.server import mcp

EXPECTED_TOOLS = {
    "scan_secrets",
    "scan_security",
    "check_bloat",
    "validate_skill",
    "verify_python_symbol",
    "verify_node_package",
    "context7_query",
    "verify_publish",
    "selftest_security",
}


def _run(coro):
    return asyncio.run(coro)


async def _list_tool_names() -> set[str]:
    async with Client(mcp) as client:
        result = await client.list_tools()
        return {t.name for t in result.tools}


async def _call(name: str, args: dict[str, Any]) -> dict[str, Any]:
    async with Client(mcp) as client:
        result = await client.call_tool(name, args)
        # O campo e `structured_content` no modelo Python do SDK v2. No wire ele
        # viaja como `structuredContent`; usar o nome do wire aqui levanta
        # AttributeError. Confirmado pelo proprio erro do pydantic.
        if result.structured_content:
            return result.structured_content
        # Fallback: conteudo textual serializado.
        return json.loads(result.content[0].text)


def test_servidor_sobe_e_expoe_todas_as_tools() -> None:
    names = _run(_list_tool_names())
    assert names >= EXPECTED_TOOLS, f"faltando: {EXPECTED_TOOLS - names}"


def test_toda_tool_tem_descricao_nao_vazia() -> None:
    async def check() -> list[str]:
        async with Client(mcp) as client:
            result = await client.list_tools()
            return [t.name for t in result.tools if not (t.description or "").strip()]

    assert _run(check()) == []


def test_scan_secrets_pelo_protocolo_reprova_token(tmp_path: Path) -> None:
    (tmp_path / "vaza.py").write_text(
        # genuino:fixture: literal falso, existe para provar que o gate reprova
        'K = "ghp_aBcDeFgHiJkLmNoPqRsTuVwXyZ0123456789"\n',
        encoding="utf-8",
    )
    payload = _run(_call("scan_secrets", {"root": str(tmp_path)}))
    assert payload["status"] == "FAIL"
    assert payload["findings"]


def test_verify_python_symbol_pelo_protocolo() -> None:
    payload = _run(_call("verify_python_symbol", {"dotted": "mcp.server.MCPServer"}))
    assert payload["status"] == "PASS"


def test_verify_publish_bloqueia_quando_um_gate_reprova(tmp_path: Path) -> None:
    (tmp_path / "vaza.py").write_text(
        # genuino:fixture: literal falso, existe para provar que o gate reprova
        'K = "ghp_aBcDeFgHiJkLmNoPqRsTuVwXyZ0123456789"\n',
        encoding="utf-8",
    )
    payload = _run(_call("verify_publish", {"root": str(tmp_path)}))
    assert payload["status"] == "FAIL"
    assert payload["gates"]["secrets"]["status"] == "FAIL"


def test_verify_publish_aprova_arvore_limpa(tmp_path: Path) -> None:
    (tmp_path / "app.py").write_text("def soma(a, b):\n    return a + b\n", encoding="utf-8")
    payload = _run(_call("verify_publish", {"root": str(tmp_path)}))
    assert payload["status"] == "PASS"


def test_context7_pelo_protocolo_nao_finge_resposta() -> None:
    payload = _run(_call("context7_query", {"library": "react"}))
    assert payload["status"] == "INDETERMINADO"
