"""Gate de publicacao como CLI, para uso na CI e antes de qualquer push.

As mesmas funcoes que o servidor MCP expoe como tools, rodadas de uma vez sobre
a arvore inteira. Existe porque um gate que so roda quando alguem lembra de
chamar nao e um gate -- e uma sugestao.

Uso:
    python -m genuino_mcp.check_tree <caminho>

Contrato de exit code, o mesmo do resto do metodo:
    0  todos os gates passaram
    1  reprovacao medida
    2  algum gate nao pode medir; NAO e aprovacao
"""

from __future__ import annotations

import sys
from pathlib import Path

from .gates import (
    FAIL,
    INDETERMINADO,
    PASS,
    GateResult,
    check_bloat,
    scan_secrets,
    selftest_security,
)


def _render(name: str, result: GateResult) -> None:
    print(f"[{result.status}] {name}: {result.summary}")
    for finding in result.findings:
        print(f"    {finding.path}:{finding.line} [{finding.rule}] {finding.excerpt[:120]}")
    for limit in result.limits:
        print(f"    limite: {limit}")


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    root = Path(args[0] if args else ".").resolve()

    if not root.is_dir():
        print(f"[INDETERMINADO] caminho nao e um diretorio: {root}")
        return 2

    print(f"Gate de publicacao sobre: {root}")

    # `method/` e conteudo normativo importado byte a byte de uma origem selada.
    # Ele responde ao gate de selo (genuino_mcp.seal), que prova que ninguem o
    # alterou. Medir estilo de codigo ali geraria achados sobre os quais ninguem
    # pode agir: refatorar quebraria o selo, e reescrever artefato selado e
    # justamente o que o metodo classifica como violacao grave.
    #
    # A varredura de segredos continua valendo para method/. Selado ou nao,
    # nada com formato de credencial entra num repositorio publico.
    # `.semgrep/` e isento da varredura de segredos porque os arquivos de regra
    # CONTEM os padroes que definem um segredo -- inclusive o cabecalho literal
    # de uma chave privada. Escanea-los faz o detector encontrar a propria
    # definicao e reportar como vazamento.
    #
    # A isencao e estreita e o diretorio nao fica sem verificacao: ele tem gate
    # proprio em `selftest_security`, que exige que essas mesmas regras
    # continuem detectando os casos de controle.
    results = {
        "scan_secrets": scan_secrets(root, allow_paths=(".semgrep/",)),
        "check_bloat": check_bloat(root, skip_paths=("method/",)),
        # O selftest roda ANTES de qualquer scan valer alguma coisa: um ruleset
        # vazio faria o scan devolver PASS em silencio, e PASS sem deteccao e
        # indistinguivel de seguranca real para quem le o relatorio.
        "selftest_security": selftest_security(root),
    }
    for name, result in results.items():
        _render(name, result)

    statuses = [r.status for r in results.values()]

    if FAIL in statuses:
        print("\nGATE DE PUBLICACAO: BLOQUEADO -- ao menos um gate reprovou.")
        return 1
    if INDETERMINADO in statuses:
        # Nao medir nao e aprovar. Um CI que tratasse isto como sucesso
        # publicaria uma arvore que ninguem conferiu.
        print("\nGATE DE PUBLICACAO: NAO LIBERADO -- ao menos um gate nao pode medir.")
        return 2

    assert all(s == PASS for s in statuses)
    print("\nGATE DE PUBLICACAO: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
