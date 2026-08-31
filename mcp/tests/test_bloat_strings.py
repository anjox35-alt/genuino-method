"""Chave em string literal, nas linguagens que o gate realmente mede.

Arquivo separado de `test_gates.py` por uma razao medida: aquele bateu no teto
de 600 linhas do proprio `check_bloat`, e o gate acusou o oraculo. Dividir e a
resposta certa; encher o teto e depois relaxa-lo seria desligar a regua para
caber.

Duas propriedades das fixtures daqui nao sao decoracao, e as duas foram pagas
com erro meu na mesma sessao:

- Existe codigo de top-level DEPOIS da funcao. Sem esse rabo, uma funcao que
  termina junto com o arquivo mede o mesmo numero pela contagem certa e pelo
  fallback de EOF, e o teste fica verde sem distinguir os dois.
- O rabo e LONGO. Com dez linhas, o estouro chega a 15 e passa despercebido sob
  um teto de 20: o defeito acontece e o gate nao o reporta. A primeira versao
  deste arquivo passava por isso, medindo nada.
"""

from __future__ import annotations

from pathlib import Path

from genuino_mcp import gates

# Construidos por chr() em vez de literal: uma crase dentro de string neste
# arquivo e exatamente o caso em discussao, e escreve-la crua aqui convida o
# proximo leitor a se enganar sobre qual nivel esta sendo citado.
CRASE = chr(96)
ASPAS = chr(34)

# Longo o bastante para que o fim-por-EOF ultrapasse o teto do teste com folga.
RABO = "\n".join(f"Write-Output depois-{i}" for i in range(200))


def _acusou_funcao_longa(tmp_path: Path, nome: str, corpo: list[str]) -> bool:
    """Escreve a fixture e devolve se `check_bloat` acusou funcao longa."""
    fonte = "function F {\n" + "\n".join(corpo) + "\n}\n\n" + RABO + "\n"
    (tmp_path / nome).write_text(fonte, encoding="utf-8")
    resultado = gates.check_bloat(
        tmp_path, gates.BloatThresholds(max_file_lines=9999, max_function_lines=20)
    )
    return any(f.rule == "funcao-longa" for f in resultado.findings)


def test_aspa_escapada_por_crase_nao_expoe_a_chave(tmp_path: Path) -> None:
    """PowerShell escapa com crase, nao com barra invertida.

    Achado da contra-auditoria, confirmado por medicao contra o patch real: uma
    implementacao que so conheca o escape C-style encerra a string na aspa
    escapada, deixa a chave de fora do recorte, e a conta como estrutura.

    Isto importa mais neste repositorio do que pareceria: o motor inteiro e
    escrito em PowerShell, e `check_bloat` mede `.ps1`.
    """
    linha = "    Write-Output " + ASPAS + "A " + CRASE + ASPAS + " { " + CRASE + ASPAS + " B" + ASPAS
    assert not _acusou_funcao_longa(tmp_path, "escape.ps1", [linha, "    Write-Output 1"]), (
        "a aspa escapada por crase encerrou a string cedo demais, a chave vazou "
        "para a contagem, e a funcao de 4 linhas engoliu o arquivo"
    )


def test_template_literal_nao_expoe_a_chave(tmp_path: Path) -> None:
    """JS e TS delimitam string tambem por crase, e o gate mede as duas.

    `_FUNC_START` reconhece `function` e arrow functions, e o escopo padrao de
    `check_bloat` inclui `.js`, `.mjs` e `.ts`. Uma implementacao que so cubra
    aspas simples e duplas deixa a chave do template literal na contagem, e a
    missao pede a regra "em qualquer das linguagens que o gate mede".
    """
    corpo = ["    const s = " + CRASE + "abre { aqui" + CRASE + ";", "    return s;"]
    assert not _acusou_funcao_longa(tmp_path, "template.ts", corpo), (
        "a chave dentro do template literal foi contada como estrutura"
    )


def test_a_correcao_nao_cega_o_gate_nas_novas_aspas(tmp_path: Path) -> None:
    """Ignorar a crase nao pode virar ignorar a linha inteira.

    O par de sempre: os dois testes acima matam quem conta demais, este mata
    quem para de contar.

    A fixture e desenhada contra o atalho especifico: a linha que abre o bloco
    interno TAMBEM carrega uma string com crase. Uma implementacao que
    descartasse a linha inteira perderia essa abertura, e entao a chave que
    fecha o `if` encerraria a funcao com 4 linhas em vez de 65 -- o gate ficaria
    mudo sobre uma funcao genuinamente longa.
    """
    corpo = ["    if ($x -eq " + ASPAS + "a" + CRASE + ASPAS + "b" + ASPAS + ") {"]
    corpo += ["        Write-Output 'dentro'", "    }"]
    corpo += [f"    Write-Output {i}" for i in range(60)]
    assert _acusou_funcao_longa(tmp_path, "grande.ps1", corpo), (
        "funcao de 65 linhas deixou de ser detectada: a correcao virou cegueira"
    )
