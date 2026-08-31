"""Verificacao de API de biblioteca contra o que esta REALMENTE instalado.

Este e o gate que ataca a adivinhacao mais cara: o modelo escreve o import ou a
chamada mais provavel do treino, e o codigo falha na maquina de quem roda.

A fonte de verdade aqui nao e a documentacao generica de uma versao qualquer da
biblioteca. E o pacote instalado neste projeto. Documentacao descreve a versao
que o autor dela tinha em mente; o interpretador descreve a que voce tem.

Caso concreto que originou este modulo: o SDK Python do MCP esta na v2 e expoe
`mcp.server.MCPServer`. A API `FastMCP` e da v1. Um modelo gerando de memoria
escreve o import da v1 e produz um servidor que nao sobe. Uma chamada a
`verify_library_api("mcp", "mcp.server.MCPServer")` responde isso em milissegundos,
offline e sem chave de API.
"""

from __future__ import annotations

import importlib
import importlib.metadata as md
import json
from pathlib import Path

from .gates import FAIL, INDETERMINADO, PASS, GateResult


def verify_python_symbol(dotted: str) -> GateResult:
    """Confirma que `dotted` existe no ambiente Python atual.

    `dotted` e um caminho como `mcp.server.MCPServer` ou `pathlib.Path`.
    """
    if not dotted or "." not in dotted:
        return GateResult(
            status=INDETERMINADO,
            summary="Informe um caminho pontuado, por exemplo 'mcp.server.MCPServer'.",
        )

    parts = dotted.split(".")

    # Tenta o prefixo mais longo que importa como modulo; o resto e atributo.
    for split in range(len(parts) - 1, 0, -1):
        module_name = ".".join(parts[:split])
        attrs = parts[split:]
        try:
            module = importlib.import_module(module_name)
        except ImportError:
            continue
        except Exception as exc:  # modulo existe mas explode ao importar
            return GateResult(
                status=INDETERMINADO,
                summary=f"'{module_name}' falhou ao importar: {exc}",
            )

        obj = module
        trail = module_name
        for attr in attrs:
            if not hasattr(obj, attr):
                return GateResult(
                    status=FAIL,
                    summary=f"'{trail}' nao expoe '{attr}'. '{dotted}' nao existe aqui.",
                    limits=[_version_note(parts[0])],
                )
            obj = getattr(obj, attr)
            trail = f"{trail}.{attr}"

        return GateResult(
            status=PASS,
            summary=f"'{dotted}' existe: {obj!r}",
            limits=[_version_note(parts[0])],
        )

    return GateResult(
        status=FAIL,
        summary=f"Nenhum prefixo de '{dotted}' pode ser importado neste ambiente.",
        limits=["Pacote nao instalado, ou nome errado."],
    )


def _version_note(top_level: str) -> str:
    try:
        return f"Versao instalada de '{top_level}': {md.version(top_level)}"
    except md.PackageNotFoundError:
        return f"Versao de '{top_level}' nao declarada nos metadados instalados."


def verify_node_package(root: Path, package: str) -> GateResult:
    """Confirma a versao instalada de um pacote Node, lendo node_modules.

    Le o `package.json` do pacote instalado, nao o do projeto: a faixa declarada
    (`^1.2.0`) nao diz qual versao foi de fato resolvida.
    """
    installed = root / "node_modules" / package / "package.json"
    if not installed.exists():
        declared = root / "package.json"
        if not declared.exists():
            return GateResult(
                status=INDETERMINADO,
                summary=f"Nem node_modules/{package} nem package.json existem em {root}.",
            )
        return GateResult(
            status=FAIL,
            summary=f"'{package}' nao esta instalado em node_modules.",
            limits=["Rode a instalacao de dependencias antes de confiar neste veredito."],
        )

    try:
        data = json.loads(installed.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        return GateResult(
            status=INDETERMINADO,
            summary=f"package.json de '{package}' ilegivel: {exc}",
        )

    version = data.get("version", "?")
    return GateResult(
        status=PASS,
        summary=f"'{package}' instalado na versao {version}.",
        limits=["Confirma a versao resolvida, nao que a API usada exista nela."],
    )


# Registrado no .mcp.json ao lado deste servidor, nao aninhado dentro dele.
# StreamableHTTPTransport.__init__ do SDK mcp 2.1.1 aceita apenas `url`, sem
# cabecalho -- entao um passthrough autenticado exigiria contornar a API publica
# do SDK. Compor MCPs lado a lado no cliente e o caminho suportado.
CONTEXT7_SERVER_URL = "https://mcp.context7.com/mcp"


def context7_guidance(library: str, topic: str = "") -> GateResult:
    """Devolve a consulta a fazer no Context7. Nao inventa a resposta.

    Este gate existe para tornar a etapa obrigatoria e rastreavel: antes de usar
    a API de uma biblioteca de terceiro, resolva o library-id e cite a fonte.
    """
    if not library.strip():
        return GateResult(
            status=INDETERMINADO,
            summary="Informe o nome da biblioteca a consultar.",
        )

    focus = f", topico '{topic}'" if topic.strip() else ""
    return GateResult(
        status=INDETERMINADO,
        summary=(
            f"Consulta pendente para '{library}'{focus}. "
            f"Chame 'resolve-library-id' e depois 'get-library-docs' no servidor "
            f"Context7 ({CONTEXT7_SERVER_URL}) e registre o library-id resolvido."
        ),
        limits=[
            "Este servidor nao faz proxy do Context7 e nao tem a resposta.",
            "Sem library-id resolvido, a resposta nao e citavel como fonte.",
            "Para a API do ambiente local, prefira verify_python_symbol: e evidencia direta.",
        ],
    )
