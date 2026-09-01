#!/bin/sh
# PreToolUse: recusa escrita no oraculo enquanto uma missao esta em curso.
#
# O oraculo e o contrato do gerente. Se ele muda durante a missao, o operario
# passa a ser medido por uma regua diferente da que recebeu -- e o GREEN deixa
# de significar o que diz.
#
# O motor ja protege o oraculo do OPERARIO, filtrando o patch. Este hook
# protege do GERENTE, que edita com as proprias ferramentas e nao passa por
# filtro nenhum.
#
# Nao bloqueia fora de missao: escrever o oraculo ANTES de delegar e o passo 1
# do fluxo R7. O sentinela `runs/.missao-ativa` distingue os dois momentos.

raiz=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
sentinela="$raiz/runs/.missao-ativa"

# Sem missao em curso, nada a proteger.
[ -f "$sentinela" ] || exit 0

alvo=$(python -c "
import json,sys
try:
    d = json.load(sys.stdin)
except Exception:
    print('')
    sys.exit(0)
ti = d.get('tool_input') or {}
print(ti.get('file_path') or ti.get('path') or '')
" 2>/dev/null)

[ -n "$alvo" ] || exit 0

# Normaliza separador do Windows para comparar um caminho so.
# Um backslash solto entre aspas simples faz o GNU tr avisar "unescaped
# backslash at end of string". `\134` e o mesmo caractere em octal, sem
# ambiguidade de escape.
# `\` e o mesmo caractere em octal, sem ambiguidade de escape.
#
# E minusculas porque o NTFS nao distingue caixa: `mcp/Tests/t.py` E
# `mcp/tests/t.py`, o mesmo arquivo. Sem isso o `case` abaixo e sensivel a
# caixa, e a protecao do oraculo cai com a tecla shift. Medido antes do
# conserto, sob missao ativa: `mcp/Tests/` e `MCP/TESTS/` passavam.
#
# Minusculiza so a copia de comparacao. `$alvo` original fica intocado: num
# filesystem que distingue caixa ele e o unico caminho que existe de verdade.
normalizado=$(printf '%s' "$alvo" | tr '\134' '/' | tr 'A-Z' 'a-z')

case "$normalizado" in
    */mcp/tests/*)
        missao=$(cat "$sentinela" 2>/dev/null)

        # Aspas SIMPLES no `-c`: o shell nao expande nada dentro da fonte, que
        # deixa de ser um template e passa a ser codigo literal. O id entra por
        # argv, que o python le como dado.
        #
        # Antes, com aspas duplas, `$missao` era concatenado na fonte e caia
        # dentro de uma string de aspas simples. Um id contendo `'` ou uma
        # quebra de linha fechava a string e produzia SyntaxError -- e o hook
        # saia com exit 0 sem emitir deny. A protecao do oraculo sumia em
        # silencio exatamente quando havia missao em curso. Medido.
        saida=$(python -c '
import json, sys
print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason":
        "Oraculo protegido: a missao \"" + sys.argv[1] + "\" esta em curso. "
        "Alterar o teste de aceitacao agora mede o operario por uma regua "
        "diferente da que ele recebeu. Espere o veredito, ou encerre a missao "
        "removendo runs/.missao-ativa.",
}}))
' "$missao" 2>/dev/null)

        # So emite a saida do python se ela contiver mesmo um deny. Vazio,
        # erro, saida parcial: tudo cai no literal. Fechar por construcao, e
        # nao por confianca no exit code de um interpretador que pode nem ter
        # rodado.
        case "$saida" in
            *'"deny"'*)
                printf '%s\n' "$saida"
                ;;
            *)
                cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Oraculo protegido: ha missao em curso e o hook nao conseguiu montar a resposta detalhada. Nao medir nao e aprovar. Se a escrita for legitima, encerre a missao removendo runs/.missao-ativa."}}
JSON
                ;;
        esac
        exit 0
        ;;
esac
exit 0
