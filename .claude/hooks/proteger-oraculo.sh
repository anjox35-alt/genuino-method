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
        python -c "
import json
print(json.dumps({
  'hookSpecificOutput': {
    'hookEventName': 'PreToolUse',
    'permissionDecision': 'deny',
    'permissionDecisionReason':
      'Oraculo protegido: a missao \"$missao\" esta em curso. '
      'Alterar o teste de aceitacao agora mede o operario por uma regua '
      'diferente da que ele recebeu. Espere o veredito, ou encerre a missao '
      'removendo runs/.missao-ativa.'
  }
}))
"
        exit 0
        ;;
esac
exit 0
