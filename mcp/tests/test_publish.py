"""Testes de aceitacao de `genuino_mcp.publish`.

O que esta sendo medido: a decisao sobre o que de um veredito local pode virar
registro publico. A regra central e a recusa -- um sanitizador que deixa passar
o que nao reconheceu produz confianca sem lastro.

Estes testes nao tocam rede. Se um deles precisar de conexao para passar, o
recorte da missao esta errado, nao o teste.
"""

from __future__ import annotations

import hashlib
import json
import tempfile
from pathlib import Path

import pytest


def _publish():
    """Importa o modulo sob teste, adiado ate a chamada.

    Um `ImportError` no topo do arquivo e erro de COLETA: o pytest sai com 2,
    que no contrato de tres faixas significa "nao foi possivel medir". O motor
    trata isso como falha de ambiente e ABORTA sem delegar.

    Mas um modulo que ainda nao existe e precisamente o estado RED esperado no
    inicio de uma missao. Ele precisa sair com 1 -- reprovacao medida -- para
    que o loop tenha o que delegar.

    Adiar o import transforma um erro de coleta em N falhas de teste, cada uma
    com a sua mensagem. Isso descobriu-se ao escrever a primeira missao que cria
    um modulo do zero.
    """
    from genuino_mcp import publish

    return publish


VEREDITO_MINIMO = {
    "mission_id": "nucleo-01-veredito-publicavel",
    "run_id": "20260831T120000.000Z",
    "verdict": "GREEN",
    "iterations": 1,
    "write_set": ["mcp/src/genuino_mcp/"],
    "oracle_paths": ["mcp/tests/"],
    "engine_sha256": "a" * 64,
    "mission_sha256": "b" * 64,
    "notes": [],
}


def _grava(tmp_path: Path, dados: dict) -> Path:
    caminho = tmp_path / "verdict.json"
    caminho.write_text(json.dumps(dados, indent=2), encoding="utf-8")
    return caminho


def test_caminho_do_repositorio_vira_marcador(tmp_path: Path) -> None:
    dados = dict(VEREDITO_MINIMO)
    # genuino:fixture: caminho ficticio, e o dado de entrada do teste
    dados["notes"] = [r"patch aplicado em C:\Users\fulano\dev\genuino-method\mcp"]
    registro = _publish().build_public_verdict(
        _grava(tmp_path, dados),
        # genuino:fixture: caminho ficticio, e o dado de entrada do teste
        repo_root=Path(r"C:\Users\fulano\dev\genuino-method"),
    )
    texto = json.dumps(registro)
    assert "fulano" not in texto, "o nome do usuario vazou para o registro publico"
    assert "<REPO>" in texto, "o prefixo do repositorio deveria virar marcador"


def test_recusa_quando_sobra_caminho_absoluto_desconhecido(tmp_path: Path) -> None:
    """A regra central. Nao reconhecer e motivo para recusar, nao para publicar.

    Um caminho de outra unidade nao tem como ser derivado de `repo_root`. O
    sanitizador nao consegue decidir o que ele revela, entao a funcao precisa
    parar. Publicar "quase limpo" e o defeito que esta missao existe para
    impedir.
    """
    dados = dict(VEREDITO_MINIMO)
    dados["notes"] = [r"lido de D:\backup-do-cliente\segredos\notas.txt"]
    with pytest.raises(_publish().PublicacaoRecusada) as erro:
        _publish().build_public_verdict(
            _grava(tmp_path, dados),
            # genuino:fixture: caminho ficticio, e o dado de entrada do teste
            repo_root=Path(r"C:\Users\fulano\dev\genuino-method"),
        )
    assert "D:" in str(erro.value), (
        "a recusa precisa dizer QUAL caminho a motivou; "
        "uma recusa sem o trecho ofensor nao e acionavel"
    )


def test_recusa_home_alheio_ainda_que_pareca_o_da_maquina(tmp_path: Path) -> None:
    r"""A regra vale nos dois sistemas -- e o teste precisa medir a regra.

    A versao anterior deixava `tmp_dir` e `home_dir` no padrao e passava
    `repo_root=Path("/srv/genuino-method")`. Isso media a maquina de quem roda,
    nao o codigo, e errava de um jeito diferente em cada sistema:

    - No Windows, `Path("/srv/...")` vira `\srv\...`, que nao e caminho
      absoluto para o sanitizador. A recusa acontecia no proprio `repo_root`,
      antes de o `notes` ser examinado: o teste passava pelo motivo errado.
    - No Ubuntu da CI, `Path.home()` E `/home/runner`. O sanitizador fazia
      exatamente o que deve -- trocar o home real por `<HOME>` -- e portanto nao
      recusava. `DID NOT RAISE`, e a CI ficou vermelha por um acerto do produto.

    Injetar os tres diretorios torna `/home/runner/...` genuinamente
    desconhecido nas duas plataformas, que e a condicao que a recusa mede. O
    home REAL continuar virando marcador e outro comportamento, coberto por
    `test_temporario_e_home_viram_marcadores`.
    """
    dados = dict(VEREDITO_MINIMO)
    dados["notes"] = ["worktree em /home/runner/work/tmp/genuino-x"]
    with pytest.raises(_publish().PublicacaoRecusada) as erro:
        _publish().build_public_verdict(
            _grava(tmp_path, dados),
            repo_root=tmp_path / "repo",
            tmp_dir=tmp_path / "tmp",
            home_dir=tmp_path / "home",
        )
    assert "/home/runner" in str(erro.value), (
        "a recusa precisa dizer QUAL caminho a motivou; "
        "uma recusa sem o trecho ofensor nao e acionavel"
    )


@pytest.mark.parametrize(
    "absoluto",
    [
        r"D:\backup-do-cliente\notas.txt",
        r"E:\dados\exportacao.csv",
        r"\\servidor\compartilhado\segredo.txt",
        "/var/lib/postgresql/dados",
        "/opt/ferramenta-interna/config",
        # genuino:fixture: caminho ficticio, e o dado de entrada do teste
        "/Users/outrapessoa/Documents/x",
        "/srv/nao-e-o-repo/arquivo",
    ],
)
def test_recusa_qualquer_absoluto_nao_reconhecido(tmp_path: Path, absoluto: str) -> None:
    """A recusa nao pode ser uma lista dos prefixos que o teste escolheu.

    Uma auditoria independente do oraculo apontou o mutante: uma implementacao
    que fizesse `if caminho.startswith(("D:", "/home/")): recusa` passaria em
    todos os casos anteriores sem detectar nada mais. O teste estaria medindo a
    propria lista.

    Estes casos existem para que a recusa tenha de ser sobre a FORMA de caminho
    absoluto, e nao sobre prefixos enumerados. Nenhum deles pode ser derivado de
    `repo_root`, `tmp_dir` ou `home_dir` -- portanto o sanitizador nao sabe o que
    revelam, e a unica resposta correta e parar.
    """
    dados = dict(VEREDITO_MINIMO)
    dados["notes"] = [f"algo aconteceu em {absoluto}"]
    with pytest.raises(_publish().PublicacaoRecusada) as erro:
        _publish().build_public_verdict(
            _grava(tmp_path, dados),
            repo_root=tmp_path / "repo",
            tmp_dir=tmp_path / "tmp",
            home_dir=tmp_path / "home",
        )

    # Sem este assert, uma recusa generica -- "algo sobrou" -- passa nos sete
    # casos sem dizer o que a motivou. O contra-auditor apontou a lacuna: o
    # teste media que a funcao PARA, nao que a parada e acionavel.
    #
    # O trecho esperado e derivado do proprio caso, e nao duplicado numa
    # segunda lista que sairia de sincronia com a primeira: o sanitizador
    # nomeia o que casou -- o prefixo, para unidade e UNC; o caminho inteiro,
    # para raiz unix.
    barra = chr(92)
    ofensor = absoluto if absoluto.startswith("/") else absoluto.lstrip(barra).split(barra)[0]
    assert ofensor in str(erro.value), (
        f"a recusa deveria nomear o trecho ofensor {ofensor!r}; "
        "recusa que nao diz o que a motivou nao e acionavel"
    )


def test_temporario_e_home_viram_marcadores(tmp_path: Path) -> None:
    """A missao exige tres marcadores. O oraculo precisa medir os tres.

    Antes da auditoria, apenas `<REPO>` era verificado -- e uma implementacao que
    ignorasse `<TMP>` e `<HOME>` por completo passava, apesar de a missao exigir
    os tres explicitamente.
    """
    repo = tmp_path / "repo"
    tmp = tmp_path / "tmp"
    home = tmp_path / "home"
    dados = dict(VEREDITO_MINIMO)
    dados["notes"] = [
        f"worktree em {tmp / 'genuino-work-x'}",
        f"config lida de {home / '.codex' / 'config.toml'}",
        f"patch aplicado em {repo / 'mcp'}",
    ]
    registro = _publish().build_public_verdict(
        _grava(tmp_path, dados), repo_root=repo, tmp_dir=tmp, home_dir=home
    )
    texto = json.dumps(registro)
    assert "<TMP>" in texto, "o diretorio temporario deveria virar marcador"
    assert "<HOME>" in texto, "o home do usuario deveria virar marcador"
    assert "<REPO>" in texto, "a raiz do repositorio deveria virar marcador"
    assert str(tmp_path) not in texto, "um caminho real sobreviveu a sanitizacao"


@pytest.mark.parametrize(
    "ausente",
    [
        "mission_id",
        "run_id",
        "verdict",
        "iterations",
        "write_set",
        "oracle_paths",
        "engine_sha256",
        "mission_sha256",
    ],
)
def test_recusa_quando_falta_campo_obrigatorio(tmp_path: Path, ausente: str) -> None:
    """Um veredito sem os hashes que o ancoram nao e evidencia, e alegacao."""
    dados = {k: v for k, v in VEREDITO_MINIMO.items() if k != ausente}
    with pytest.raises(_publish().PublicacaoRecusada) as erro:
        _publish().build_public_verdict(_grava(tmp_path, dados), repo_root=tmp_path)
    assert ausente in str(erro.value), f"a recusa deveria nomear o campo ausente '{ausente}'"


def test_preserva_o_hash_do_arquivo_original(tmp_path: Path) -> None:
    """O elo entre o registro publico e o arquivo em disco.

    Precisa ser o hash do arquivo COMO ESTAVA, antes de qualquer sanitizacao --
    e o que permite a quem tem o original provar que o registro veio dele. Um
    hash calculado depois da transformacao nao prova nada sobre o original.
    """
    caminho = _grava(tmp_path, dict(VEREDITO_MINIMO))
    esperado = hashlib.sha256(caminho.read_bytes()).hexdigest()
    registro = _publish().build_public_verdict(caminho, repo_root=tmp_path)
    assert registro["verdict_sha256"] == esperado


def test_campos_do_veredito_sobrevivem_a_transformacao(tmp_path: Path) -> None:
    registro = _publish().build_public_verdict(
        _grava(tmp_path, dict(VEREDITO_MINIMO)), repo_root=tmp_path
    )
    assert registro["mission_id"] == "nucleo-01-veredito-publicavel"
    assert registro["verdict"] == "GREEN"
    assert registro["iterations"] == 1
    assert registro["write_set"] == ["mcp/src/genuino_mcp/"]
    assert registro["engine_sha256"] == "a" * 64


def test_os_defaults_de_tmp_e_home_sao_reais(tmp_path: Path, monkeypatch) -> None:
    """Os parametros opcionais precisam ter default utilizavel.

    Segunda auditoria independente do oraculo apontou esta lacuna: todos os
    casos passavam `tmp_dir` e `home_dir` explicitamente, entao uma
    implementacao que ignorasse os defaults -- ou os apontasse para um caminho
    inexistente -- passaria em tudo. Quem chamasse a funcao sem os argumentos,
    que e o uso normal, teria caminho pessoal vazando sem recusa.

    `monkeypatch` fixa o home para nao depender da maquina de quem roda.
    """
    home_falso = tmp_path / "home-do-usuario"
    monkeypatch.setattr(Path, "home", classmethod(lambda cls: home_falso))
    monkeypatch.setattr(tempfile, "gettempdir", lambda: str(tmp_path / "temp-do-so"))

    dados = dict(VEREDITO_MINIMO)
    dados["notes"] = [
        f"config em {home_falso / '.codex'}",
        f"worktree em {tmp_path / 'temp-do-so' / 'genuino-x'}",
    ]
    registro = _publish().build_public_verdict(_grava(tmp_path, dados), repo_root=tmp_path / "repo")
    texto = json.dumps(registro)
    assert "<HOME>" in texto, "sem `home_dir` explicito, o default deveria valer"
    assert "<TMP>" in texto, "sem `tmp_dir` explicito, o default deveria valer"


def test_o_modulo_nao_alcanca_a_rede() -> None:
    """O operario roda sem rede; o modulo tambem.

    Verificado sobre o codigo-fonte, nao sobre a execucao: um import de cliente
    de banco pode nao ser exercitado pelos outros casos e ainda assim estar la,
    esperando a proxima pessoa a chamar.
    """
    fonte = Path(_publish().__file__).read_text(encoding="utf-8")
    for proibido in ("requests", "httpx", "urllib", "socket", "psycopg", "supabase"):
        assert proibido not in fonte, (
            f"'{proibido}' aparece em publish.py; este modulo transforma e valida, nao publica"
        )


def test_recusa_absoluto_fora_do_campo_notes(tmp_path: Path) -> None:
    """A sanitizacao vale para o documento inteiro, nao para um campo escolhido.

    O contra-auditor observou que TODOS os casos anteriores injetavam o caminho
    absoluto em `notes`. Uma implementacao que sanitizasse apenas essa chave --
    e ignorasse o resto do veredito -- passaria na suite inteira.

    Aqui o caminho entra em `write_set`, que e outra chave de topo. Se a recusa
    depender do nome do campo, este teste reprova.
    """
    dados = dict(VEREDITO_MINIMO)
    dados["write_set"] = ["/opt/fora-do-repo/src/"]
    with pytest.raises(_publish().PublicacaoRecusada) as erro:
        _publish().build_public_verdict(
            _grava(tmp_path, dados),
            repo_root=tmp_path / "repo",
            tmp_dir=tmp_path / "tmp",
            home_dir=tmp_path / "home",
        )
    assert "/opt/fora-do-repo" in str(erro.value)


def test_hash_e_do_original_ainda_que_a_sanitizacao_mude_bytes(tmp_path: Path) -> None:
    """O elo com o arquivo em disco, medido onde ele pode quebrar.

    `test_preserva_o_hash_do_arquivo_original` roda sobre um veredito ja limpo,
    onde a sanitizacao nao altera um byte. Nesse caso o hash de ANTES e o hash de
    DEPOIS sao identicos, e uma implementacao que hasheasse o resultado
    sanitizado passaria sem ser detectada -- foi o achado do contra-auditor.

    Aqui o conteudo MUDA na sanitizacao: o caminho do repositorio vira `<REPO>`.
    Os dois hashes passam a divergir, e so o do arquivo original satisfaz o
    assert. Este e o teste que mata aquele mutante.
    """
    repo = tmp_path / "repo"
    dados = dict(VEREDITO_MINIMO)
    dados["notes"] = [f"patch aplicado em {repo / 'mcp'}"]
    caminho = _grava(tmp_path, dados)
    esperado = hashlib.sha256(caminho.read_bytes()).hexdigest()

    registro = _publish().build_public_verdict(
        caminho, repo_root=repo, tmp_dir=tmp_path / "tmp", home_dir=tmp_path / "home"
    )

    assert "<REPO>" in json.dumps(registro), (
        "pre-condicao do teste: a sanitizacao precisa ter alterado o conteudo, "
        "senao os dois hashes coincidem e o mutante sobrevive"
    )
    assert registro["verdict_sha256"] == esperado
