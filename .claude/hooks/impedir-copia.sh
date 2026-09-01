#!/bin/sh
# PreToolUse: recusa a criacao de arquivo com nome de copia (R4).
#
# A R4 proibe `*_v2*`, `*_copy*`, `*_final*`, `*_new*`, `*_backup*`, `*_old*` e
# `* (1)*`, e diz textualmente que "a regra vale mesmo se o hook falhar" --
# pressupondo um hook. Ele nao existia: uma busca pelos padroes em `mcp/src`,
# `engine`, `.github/workflows`, `.claude` e `.githooks` nao devolvia nenhuma
# aplicacao. A R4 era cumprida so por disciplina, e o comentario do `pre-push`
# ja registra nesta base o que acontece quando disciplina e o unico mecanismo.
#
# POR QUE O PADRAO E ANCORADO NO FIM DO NOME
#
# Os globs da R4 tem `*` dos dois lados, entao `*_final*` casa com
# `test_finalize.py`, `*_copy*` com `test_copyright.py` e `*_new*` com
# `parser_newline.md`. Um gate que reprova esses tres e desligado pelo operador
# na primeira semana -- e ai a R4 volta a ser texto, que e exatamente o estado
# que este hook existe para encerrar. Aqui o padrao so conta quando termina o
# nome ou vem antes de um ponto, que e a forma como copia de fato se chama:
# `server_v2.py`, `relatorio_final.md`, `notas (1).md`, `archive_old.tar.gz`.
#
# LIMITE CONHECIDO: `server_v2_corrigido.py` passa. O sufixo esta no meio, e
# fechar isso reabre o falso positivo. O oraculo em `test-impedir-copia.sh`
# registra a fronteira escolhida, caso o autor queira move-la.
#
# NAO BLOQUEIA ARQUIVO QUE JA EXISTE: editar um legado mal nomeado nao e criar
# uma copia, e bloquear isso deixaria o proprio legado sem conserto.
#
# FALHA ABERTO, de proposito: se o json nao parseia ou o python some, o hook
# libera. Um hook protetor que fecha em erro de ambiente trava a sessao inteira,
# e a R4 ja declara que a regra nao depende deste mecanismo para valer.

alvo_json=$(cat)

# `python` nao existe de fabrica em Linux e macOS recentes: la o binario se
# chama `python3`. Sem resolver entre os dois, o extrator nunca roda nesses
# hosts, o hook nao imprime nada, e a R4 volta a ser so texto sem que ninguem
# perceba -- o estado exato que este hook existe para encerrar. Falhar aberto
# quando NENHUM interpretador existe e a decisao declarada acima; falhar
# aberto porque o binario tem outro nome e defeito, nao decisao.
py=""
for candidato in python python3; do
    if command -v "$candidato" >/dev/null 2>&1; then
        py=$candidato
        break
    fi
done

printf '%s' "$alvo_json" | "${py:-python}" -c '
import json, os, re, sys

try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)

ti = d.get("tool_input") or {}
alvo = ti.get("file_path") or ti.get("path") or ti.get("notebook_path") or ""
if not alvo:
    sys.exit(0)

# Separador do Windows normalizado para um caminho so.
alvo = alvo.replace("\\", "/")

# Legado ja no disco: editar nao e copiar.
if os.path.exists(alvo):
    sys.exit(0)

nome = os.path.basename(alvo)

# O padrao so conta no fim do nome ou imediatamente antes de um ponto.
# `(\.|$)` e o que separa `relatorio_final.md` de `test_finalize.py`.
#
# IGNORECASE porque o NTFS nao distingue caixa: `server_V2.py` E o mesmo
# arquivo que `server_v2.py`, entao um matcher sensivel a caixa nao e mais
# restrito, e apenas contornavel pelo shift. Medido antes do conserto:
# `server_V2.py`, `server_Copy.md`, `plano_FINAL.md`, `dados_BACKUP.json`,
# `motor_Old.ps1` e `conf_New.json` passavam todos.
#
# IGNORECASE e nao `nome.lower()` por dois motivos. `str.lower()` muda o
# comprimento em alguns pontos Unicode -- o I maiusculo com ponto do turco,
# U+0130, vira dois caracteres em minusculo -- e ai o span da captura deixa
# de mapear no nome original.
# E group(1) preserva a caixa como foi digitada, entao a razao do deny diz
# `_V2`, que e o que o operador escreveu, e nao `_v2`, que pareceria erro.
achado = re.search(
    r"(_v2|_copy|_final|_new|_backup|_old|\s\(\d+\))(\.|$)",
    nome,
    re.IGNORECASE,
)
if not achado:
    sys.exit(0)

padrao = achado.group(1)
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": (
            "R4 (anti-copias): o nome \"" + nome + "\" termina em \""
            + padrao + "\". Mudanca de comportamento se faz EDITANDO o arquivo "
            "existente, nao criando um irmao versionado no nome. Se o modulo e "
            "genuinamente novo, escolha um nome que descreva o que ele faz. Se o "
            "antigo ficou obsoleto, mova para attic/ e registre motivo e origem "
            "em attic/README.md."
        ),
    }
}))
'
exit 0
