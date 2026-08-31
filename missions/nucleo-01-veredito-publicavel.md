# nucleo-01-veredito-publicavel

Primeira fatia do NÚCLEO. Fecha o limite 13 de `docs/limites.md` na parte que
tem regra: transformar um `verdict.json` local num registro que possa ser
publicado sem vazar a máquina de quem rodou.

OBJETIVO: um módulo `genuino_mcp.publish` que leia um `verdict.json` e devolva o
registro público correspondente — sanitizado, validado e recusável.

## Por que existe

`runs/` está no `.gitignore`. Toda a evidência que a R2 exige — comando, saída,
exit code, `verdict.json` — existe apenas na máquina que rodou o loop. Quem
clona este repositório tem a palavra do autor de que os gates passaram, que é
exatamente o que o método recusa aceitar em qualquer outro lugar.

O motivo do ignore é real: um run carrega caminhos absolutos do host, nomes de
worktree em `%TEMP%` e patches inteiros. Isso explica a exclusão; não a resolve.

Esta missão produz a peça que faltava para resolver: a função que decide o que
de um veredito pode virar público, e recusa quando não consegue decidir.

## Comportamento esperado

**Sanitização.** Caminho absoluto da máquina de desenvolvimento não sai daqui.
Prefixos conhecidos viram marcadores: a raiz do repositório vira `<REPO>`, o
diretório temporário vira `<TMP>`, o home do usuário vira `<HOME>`.

**Falha fechada.** Se após a sanitização ainda restar algo com forma de caminho
absoluto — `C:\...`, `/home/...`, `/Users/...` — a função **recusa** e levanta
erro. Não publica "quase limpo".

Esta é a regra central da missão. Um sanitizador que deixa passar o que não
reconheceu é pior que nenhum: produz confiança sem lastro, que é o defeito que
este repositório inteiro existe para impedir.

**Campos obrigatórios.** O registro público precisa carregar, no mínimo:
`mission_id`, `run_id`, `verdict`, `iterations`, `write_set`, `oracle_paths`,
`engine_sha256`, `mission_sha256`. Faltando qualquer um, recusa — um veredito
sem os hashes que o ancoram não é evidência, é alegação.

**Integridade do original.** O registro carrega o SHA-256 do `verdict.json` como
ele estava em disco, calculado **antes** da sanitização. É o elo que permite a
quem tem o arquivo original provar que o registro público veio dele.

**Sem rede.** Este módulo não abre conexão. Ele transforma e valida; publicar é
outra etapa, do gerente, fora do write-set desta missão.

## Assinatura

```python
class PublicacaoRecusada(Exception): ...

def build_public_verdict(
    verdict_path: Path,
    *,
    repo_root: Path,
    tmp_dir: Path | None = None,   # default: tempfile.gettempdir()
    home_dir: Path | None = None,  # default: Path.home()
) -> dict: ...
```

`tmp_dir` e `home_dir` são injetáveis porque o teste precisa controlá-los. Um
módulo que só lê `Path.home()` internamente não é testável sem depender da
máquina de quem roda — e um teste que depende da máquina não mede o código.

A exceção precisa nomear o que causou a recusa: o campo ausente, ou o trecho de
caminho que sobrou. Recusa sem o motivo não é acionável por quem a recebe.

## O que a recusa NÃO pode ser

Uma lista de prefixos. `if caminho.startswith(("D:", "/home/")): recusa` é a
implementação errada — ela reconhece o que alguém lembrou de enumerar e libera
todo o resto.

A verificação é sobre a **forma** de caminho absoluto que sobreviveu à
sanitização: unidade Windows (`X:\`), caminho UNC (`\\servidor\`), e raiz Unix
(`/algo/`). O oráculo tem casos com `E:\`, `\\servidor\`, `/var/`, `/opt/` e
`/srv/` justamente para que enumerar não seja suficiente.

Este parágrafo existe porque uma auditoria independente do oráculo, feita antes
desta missão ser delegada, encontrou exatamente esse mutante sobrevivendo à
versão anterior dos testes.

WRITE_SET: mcp/src/genuino_mcp/
ORACULO: mcp/tests/

TEST_CMD: $env:UV_LINK_MODE='copy'; Set-Location mcp; uv run pytest tests/test_publish.py -q; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; uv run ruff check .; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; uv run ruff format --check .; exit $LASTEXITCODE

FRONTEIRA: `from genuino_mcp.publish import build_public_verdict` num script do autor, sobre um verdict.json real de runs/
GATE_DA_FRONTEIRA: $env:UV_LINK_MODE='copy'; Set-Location mcp; uv run python -c "from genuino_mcp.publish import build_public_verdict; print('importavel')"; exit $LASTEXITCODE
PRE_REQUISITOS_HUMANOS: NENHUM

## STOP CONDITIONS

- Alterar qualquer arquivo em `mcp/tests/` é violação de oráculo.
- Escrever fora do `WRITE_SET` reprova a iteração.
- Dependência nova: BLOCKED. `hashlib`, `json`, `pathlib` e `re` bastam.
- Abrir conexão de rede, ou importar cliente de banco, é violação de escopo.

## Nota sobre o `TEST_CMD`

O lint está dentro do comando medido, e não por preferência de estilo.

Na missão anterior o `TEST_CMD` continha apenas `pytest`. O trabalho do operário
ficou GREEN e correto, e o `ruff` reprovou depois — em arquivo do gerente. O que
não está no `TEST_CMD` não é medido, e o que não é medido não pode ser cobrado
de ninguém.

## Nota sobre o que esta missão NÃO faz

Não cria tabela, não conecta ao Supabase, não publica nada. O esquema do banco é
contrato, e contrato é do gerente — está em `nucleo/schema/` e foi aplicado
antes desta missão existir.

O recorte não é burocrático: o operário roda sem rede. Uma missão que exigisse
conexão não poderia ser medida no worktree, e o veredito seria sobre o ambiente
em vez de sobre o trabalho.
