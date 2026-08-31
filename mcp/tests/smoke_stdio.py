"""Smoke da fronteira real: o servidor como processo separado, falando stdio.

Os testes de `test_server.py` usam o servidor em memoria. Isso prova a logica,
nao o empacotamento: um erro de entrypoint, de `__main__` ou de dependencia so
aparece quando o processo sobe de verdade. Esta e a fronteira que o cliente MCP
do usuario realmente atravessa.

Nao roda sob pytest de proposito -- subir subprocesso a cada coleta encareceria
a suite. Rode direto:

    uv run python tests/smoke_stdio.py

Exit code: 0 se tudo passou, 1 se alguma asercao falhou.
"""

from __future__ import annotations

import asyncio
import sys

from mcp import Client, StdioServerParameters

EXPECTED_TOOLS = {
    "check_bloat",
    "context7_query",
    "scan_secrets",
    "scan_security",
    "validate_skill",
    "verify_node_package",
    "verify_publish",
    "verify_python_symbol",
}


async def main() -> int:
    params = StdioServerParameters(
        command=sys.executable,
        args=["-m", "genuino_mcp.server"],
    )
    failures: list[str] = []

    async with Client(params) as client:
        listed = await client.list_tools()
        names = {t.name for t in listed.tools}
        print(f"tools expostas: {len(names)}")
        for name in sorted(names):
            print(f"  - {name}")

        missing = EXPECTED_TOOLS - names
        if missing:
            failures.append(f"tools ausentes: {sorted(missing)}")

        # O caso que originou o servidor: a API v2 existe, a v1 nao.
        v2 = await client.call_tool(
            "verify_python_symbol", {"dotted": "mcp.server.MCPServer"}
        )
        status_v2 = (v2.structured_content or {}).get("status")
        print(f"mcp.server.MCPServer (v2 atual)      -> {status_v2}")
        if status_v2 != "PASS":
            failures.append(f"esperado PASS para a API v2, obtido {status_v2}")

        v1 = await client.call_tool(
            "verify_python_symbol", {"dotted": "mcp.server.fastmcp.FastMCP"}
        )
        status_v1 = (v1.structured_content or {}).get("status")
        print(f"mcp.server.fastmcp.FastMCP (v1 legada) -> {status_v1}")
        if status_v1 != "FAIL":
            failures.append(f"esperado FAIL para a API v1, obtido {status_v1}")

    if failures:
        print("\nSMOKE FAIL")
        for f in failures:
            print(f"  {f}")
        return 1

    print("\nSMOKE PASS -- servidor sobe por stdio e os gates decidem corretamente.")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
