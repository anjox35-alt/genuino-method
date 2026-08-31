"""Servidor MCP do metodo Genuino.

Casca fina sobre `gates` e `libapi`. Toda a logica de decisao mora naqueles
modulos, que sao testaveis sem subir o protocolo.

API do SDK confirmada por introspecao em `mcp` 2.1.1:
    from mcp.server import MCPServer   # v2. `FastMCP` e a API v1, legada.
    @mcp.tool()
    mcp.run(transport="stdio")
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

from mcp.server import MCPServer

from . import gates, libapi

INSTRUCTIONS = """\
Gates de verificacao do metodo Genuino.

Use estas tools antes de afirmar que um codigo esta pronto, seguro ou correto.
Cada uma devolve um veredito em tres faixas:

  PASS          - passou, com a evidencia anexa
  FAIL          - reprovacao medida, com arquivo e linha
  INDETERMINADO - nao foi possivel medir; e falha de ambiente, nao aprovacao

INDETERMINADO nunca deve ser tratado como PASS. Se um gate nao pode medir, a
alegacao correspondente continua nao verificada.
"""

mcp = MCPServer(
    name="genuino",
    version="0.1.0",
    instructions=INSTRUCTIONS,
)


def _resolve(path: str) -> Path:
    return Path(path).expanduser().resolve()


@mcp.tool()
def scan_secrets(root: str, allow_paths: list[str] | None = None) -> dict[str, Any]:
    """Procura segredo, token e caminho pessoal numa arvore de arquivos.

    Rode antes de qualquer push para repositorio publico. Caminho pessoal conta
    como achado: 'C:\\Users\\<nome>' identifica a pessoa tao bem quanto um token.

    Args:
        root: diretorio a varrer.
        allow_paths: prefixos relativos a ignorar, por exemplo ["docs/exemplos/"].
    """
    return gates.scan_secrets(_resolve(root), allow_paths or []).to_dict()


@mcp.tool()
def scan_security(root: str, config: str = "auto") -> dict[str, Any]:
    """Roda o semgrep local sobre uma arvore e devolve os achados.

    Sem semgrep no PATH, devolve INDETERMINADO em vez de PASS: ausencia de
    ferramenta nao e ausencia de vulnerabilidade.

    Args:
        root: diretorio a analisar.
        config: config do semgrep. 'auto' usa o conjunto padrao de regras.
    """
    return gates.scan_security(_resolve(root), config=config).to_dict()


@mcp.tool()
def check_bloat(
    root: str,
    max_file_lines: int = 600,
    max_function_lines: int = 80,
) -> dict[str, Any]:
    """Mede tres sintomas contaveis de inflacao: arquivo longo, funcao longa e
    bloco duplicado.

    Nao julga necessidade nem corretude. Aponta o candidato a revisao.

    Args:
        root: diretorio a medir.
        max_file_lines: teto de linhas por arquivo.
        max_function_lines: teto aproximado de linhas por funcao.
    """
    thresholds = gates.BloatThresholds(
        max_file_lines=max_file_lines,
        max_function_lines=max_function_lines,
    )
    return gates.check_bloat(_resolve(root), thresholds).to_dict()


@mcp.tool()
def validate_skill(path: str) -> dict[str, Any]:
    """Valida um arquivo SKILL.md: frontmatter com allowlist estrita, 'name' em
    kebab-case ASCII, 'description' presente e nenhum TODO no corpo.

    Args:
        path: caminho do SKILL.md.
    """
    return gates.validate_skill(_resolve(path)).to_dict()


@mcp.tool()
def verify_python_symbol(dotted: str) -> dict[str, Any]:
    """Confirma que um simbolo Python existe no ambiente instalado AGORA.

    Use antes de escrever um import de biblioteca cuja versao voce nao verificou.
    Documentacao descreve a versao que o autor dela tinha; o interpretador
    descreve a que voce tem.

    Args:
        dotted: caminho pontuado, por exemplo 'mcp.server.MCPServer'.
    """
    return libapi.verify_python_symbol(dotted).to_dict()


@mcp.tool()
def verify_node_package(root: str, package: str) -> dict[str, Any]:
    """Le a versao REALMENTE resolvida de um pacote em node_modules.

    A faixa declarada no package.json ('^1.2.0') nao diz qual versao foi
    instalada.

    Args:
        root: raiz do projeto Node.
        package: nome do pacote, por exemplo '@openai/codex'.
    """
    return libapi.verify_node_package(_resolve(root), package).to_dict()


@mcp.tool()
def context7_query(library: str, topic: str = "") -> dict[str, Any]:
    """Monta a consulta a fazer no servidor Context7 e exige library-id resolvido.

    Este servidor nao faz proxy do Context7 e nao inventa a resposta: devolve
    INDETERMINADO com a consulta pendente. Registre o Context7 lado a lado no
    seu cliente MCP.

    Args:
        library: nome da biblioteca.
        topic: assunto especifico, opcional.
    """
    return libapi.context7_guidance(library, topic).to_dict()


@mcp.tool()
def verify_publish(root: str, allow_paths: list[str] | None = None) -> dict[str, Any]:
    """Portao unico antes de publicar: roda scan_secrets e check_bloat juntos.

    Reprova se qualquer um reprovar. Se algum ficar INDETERMINADO, o veredito
    global e INDETERMINADO, nunca PASS.

    Args:
        root: raiz da arvore a publicar.
        allow_paths: prefixos relativos isentos da varredura de segredos.
    """
    target = _resolve(root)
    results = {
        "secrets": gates.scan_secrets(target, allow_paths or []),
        "bloat": gates.check_bloat(target),
    }

    if any(r.status == gates.FAIL for r in results.values()):
        status = gates.FAIL
        summary = "Publicacao BLOQUEADA: ao menos um gate reprovou."
    elif any(r.status == gates.INDETERMINADO for r in results.values()):
        status = gates.INDETERMINADO
        summary = "Publicacao NAO LIBERADA: ao menos um gate nao pode medir."
    else:
        status = gates.PASS
        summary = "Gates de publicacao aprovados."

    return {
        "status": status,
        "summary": summary,
        "gates": {name: r.to_dict() for name, r in results.items()},
    }


def main() -> None:
    """Ponto de entrada. Fala stdio, que e o transporte padrao do SDK."""
    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
