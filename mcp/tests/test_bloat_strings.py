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

import re
from pathlib import Path

import pytest

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
    linha = (
        "    Write-Output " + ASPAS + "A " + CRASE + ASPAS + " { " + CRASE + ASPAS + " B" + ASPAS
    )
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


def _comprimento_reportado(findings: list, arquivo: str) -> int | None:
    """Devolve o comprimento que o gate MEDIU, e nao apenas se ele acusou.

    Duplicado de `test_gates.py` de proposito: sao cinco linhas, e importar
    entre modulos de teste acopla dois arquivos que o pytest coleta de forma
    independente.

    LIMITE CONHECIDO, o mesmo la e aqui: isto le o texto do `excerpt`, porque
    `Finding` nao expoe campo numerico de comprimento. Uma mudanca so de
    redacao no `excerpt` produz RED falso. Dar a `Finding` um campo tipado
    vive em `core.py`, fora do write-set desta missao, e fica como candidata.
    """
    for f in findings:
        if f.rule == "funcao-longa" and f.path.endswith(arquivo):
            achado = re.search(r"~(\d+) linhas", f.excerpt)
            if achado:
                return int(achado.group(1))
    return None


def _mede(tmp_path: Path, nome: str, corpo: list[str]) -> int | None:
    """Escreve a fixture e devolve o comprimento medido, nao apenas se acusou."""
    fonte = "function F {\n" + "\n".join(corpo) + "\n}\n\n" + RABO + "\n"
    (tmp_path / nome).write_text(fonte, encoding="utf-8")
    resultado = gates.check_bloat(
        tmp_path, gates.BloatThresholds(max_file_lines=9999, max_function_lines=20)
    )
    return _comprimento_reportado(resultado.findings, nome)


def test_funcao_longa_em_ts_e_medida_no_fim_exato(tmp_path: Path) -> None:
    """A correcao para JS/TS nao pode virar cegueira para JS/TS.

    Lacuna encontrada pela contra-auditoria ANTES da delegacao, e confirmada
    por medicao do gerente: dos quatro asserts do oraculo que EXIGEM deteccao,
    tres usavam `.ps1` e um usava `.py`. Nenhum usava `.ts`, `.js` ou `.mjs`.

    O unico teste que cobria TypeScript exigia que uma funcao CURTA nao fosse
    reportada. Com so aquele, uma implementacao que simplesmente parasse de
    contar chaves nessas tres extensoes passava no oraculo inteiro e deixava o
    gate cego para elas. E o mesmo mutante que
    `test_a_correcao_nao_cega_o_gate_nas_novas_aspas` mata do lado do
    PowerShell, e que do lado do JS nao tinha quem matasse.

    A fixture e desbalanceada de proposito, na mesma forma que a de
    `test_funcao_longa_com_string_e_medida_no_fim_exato`: dez aberturas em
    literal contra um fechamento. Sem esse desequilibrio o par extra de chaves
    se cancela, a contagem crua acerta por acidente, e o teste nasce verde sem
    medir nada.
    """
    # Bloco real cuja linha de abertura TAMBEM carrega template literal com chave.
    corpo = ["    if (x === " + CRASE + "prefixo {" + CRASE + ") {"]
    corpo += ["        console.log('dentro');", "    }"]
    # Dez aberturas em literal: garantem que a contagem crua ja esteja
    # desbalanceada quando o fechamento em literal aparecer.
    corpo += [f"    const a{i} = " + CRASE + "json quebrado: {" + CRASE + ";" for i in range(10)]
    # Fechamento em literal: mata o sanitizador unilateral, que ignora `{` entre
    # crases e continua contando `}`.
    corpo += ["    const fim = " + CRASE + "fim do bloco }" + CRASE + ";"]
    corpo += [f"    const v{i} = {i};" for i in range(50)]

    medido = _mede(tmp_path, "longa.ts", corpo)
    assert medido is not None, (
        "funcao longa em TypeScript deixou de ser detectada: o tratamento de "
        "template literal virou cegueira para a linguagem inteira"
    )
    esperado = len(corpo) + 2
    assert medido == esperado, (
        f"o gate mediu {medido} linhas em .ts, e a funcao tem {esperado}. "
        "Igualdade, e nao faixa: faixa aceita o off-by-one"
    )


def test_sem_o_analisador_o_gate_degrada_e_nao_quebra(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Ausencia do analisador e faixa >=2, e faixa >=2 nao pode virar excecao.

    Lacuna encontrada pela contra-auditoria antes da delegacao: a missao exige
    que o gate caia na contagem de chaves quando o interpretador do PowerShell
    nao existe, mas nenhum teste exercitava esse caminho. Uma implementacao que
    levantasse excecao fatal passaria no oraculo, e entao `check_bloat`
    quebraria em qualquer maquina sem PowerShell -- o runner `ubuntu-latest` da
    CI inclusive, se um dia deixar de traze-lo pre-instalado.

    Os dois monkeypatches cobrem as duas formas de descobrir a ausencia, porque
    o oraculo nao dita a implementacao: quem consulta `shutil.which` antes, e
    quem simplesmente chama e trata `FileNotFoundError`.

    `_git_tracked_files` captura `OSError` e cai no `rglob`, entao derrubar o
    `subprocess.run` nao cega a listagem de arquivos. Verificado em `core.py`.
    """
    monkeypatch.setattr(gates.shutil, "which", lambda _name: None)

    def sem_executavel(*_args, **_kwargs):
        raise FileNotFoundError("interpretador ausente")

    monkeypatch.setattr(gates.subprocess, "run", sem_executavel)

    corpo = [f"    Write-Output {i}" for i in range(60)]
    medido = _mede(tmp_path, "degrada.ps1", corpo)
    esperado = len(corpo) + 2
    assert medido == esperado, (
        f"sem o analisador o gate mediu {medido} e a funcao tem {esperado}: a "
        "degradacao para contagem de chaves nao aconteceu, ou o gate quebrou"
    )


def test_chave_de_fechamento_em_string_nao_encerra_a_funcao_cedo(tmp_path: Path) -> None:
    """O flanco simetrico: a contagem crua tambem erra para MENOS.

    Todas as outras fixtures deste oraculo tem a contagem crua estourando ate o
    EOF, ou acertando. Nenhuma a fazia FECHAR CEDO. Medido nas sete anteriores:
    205/4, 205/4, 205/4, 267/66, 65/65, 3/3, 62/62 -- a crua nunca ficava ABAIXO
    da verdade.

    Isso deixava vivo um mutante que passa em 100% do oraculo:

        fim = _parser_end(...)
        return min(fim, _contagem(...)) if fim is not None else _contagem(...)

    Com a crua sempre igual ou maior, `min` e indistinguivel do parser puro --
    min(4, 205) = 4, min(66, 267) = 66, min(65, 65) = 65. Passa tudo, e emudece
    o gate no caso desta fixture.

    A causa esta escrita no proprio oraculo: em
    `test_funcao_longa_com_string_e_medida_no_fim_exato` as dez aberturas em
    literal vem ANTES do fechamento em literal, de proposito, "para que o
    defeito atual continue estourando ate o EOF em vez de fechar cedo". A
    escolha que mata o sanitizador unilateral garante, de quebra, que a crua
    nunca subestime -- e deixa este flanco aberto.

    Aqui a ordem e invertida: o fechamento em string vem sem nenhuma abertura em
    string antes. Medido contra a implementacao atual: crua = 2, verdade = 63.
    Uma funcao de 63 linhas desaparece do gate sob teto de 20.

    Achado da revisao adversarial antes da delegacao, confirmado por medicao.
    """
    corpo = ["    Write-Output 'fecha aqui: }'"]
    corpo += [f"    Write-Output {i}" for i in range(60)]

    medido = _mede(tmp_path, "fecha-cedo.ps1", corpo)
    assert medido is not None, (
        "funcao de 63 linhas nao foi reportada: a chave de fechamento dentro da "
        "string encerrou a contagem na segunda linha, e o gate ficou mudo"
    )
    esperado = len(corpo) + 2
    assert medido == esperado, (
        f"o gate mediu {medido} linhas e a funcao tem {esperado}. Se o valor for "
        "menor que o real, o resultado do parser foi combinado com a contagem "
        "crua em vez de substitui-la"
    )
