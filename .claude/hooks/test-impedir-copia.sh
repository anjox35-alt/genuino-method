#!/bin/sh
# Oraculo do hook anti-copia da R4.
#
# O hook decide sobre NOMES, e nome tem borda ambigua: `_final` esta dentro de
# `_finalize`, `_copy` dentro de `_copyright`, `_new` dentro de `_newline`.
# Um gate que reprova `test_finalize.py` e desligado pelo operador na primeira
# semana, e ai a R4 volta a ser so texto. Por isso metade dos casos abaixo
# existe para provar o que o hook NAO pode bloquear.
#
# Uso: sh .claude/hooks/test-impedir-copia.sh
# Exit 0 = todos os casos passaram. Exit 1 = ha caso reprovado.

raiz=$(git rev-parse --show-toplevel) || exit 2
hook="$raiz/.claude/hooks/impedir-copia.sh"

falhas=0
total=0

# Alimenta o hook com um evento PreToolUse e devolve "deny" ou "allow".
decidir() {
    saida=$(printf '{"hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{"file_path":"%s"}}' "$2" "$1" | sh "$hook" 2>/dev/null)
    case "$saida" in
        *'"deny"'*) echo "deny" ;;
        *)          echo "allow" ;;
    esac
}

verificar() {
    caminho="$1"
    esperado="$2"
    motivo="$3"
    total=$((total + 1))
    obtido=$(decidir "$caminho" "Write")
    if [ "$obtido" = "$esperado" ]; then
        printf '  ok    %-8s %-42s %s\n' "$obtido" "$caminho" "$motivo"
    else
        printf '  FALHA esperado=%s obtido=%s  %-30s %s\n' "$esperado" "$obtido" "$caminho" "$motivo" >&2
        falhas=$((falhas + 1))
    fi
}

echo "== deve BLOQUEAR: sufixo de copia no fim do nome =="
verificar "$raiz/mcp/src/genuino_mcp/server_v2.py" deny  "R4: _v2"
verificar "$raiz/docs/notas_copy.md"               deny  "R4: _copy"
verificar "$raiz/docs/relatorio_final.md"          deny  "R4: _final"
verificar "$raiz/mcp/config_new.json"              deny  "R4: _new"
verificar "$raiz/engine/motor_old.ps1"             deny  "R4: _old"
verificar "$raiz/dump_backup.sql"                  deny  "R4: _backup"
verificar "$raiz/docs/notas (1).md"                deny  "R4: (1) do Windows"
verificar "$raiz/docs/notas (2).md"                deny  "(2) e a mesma copia"
verificar "$raiz/archive_old.tar.gz"               deny  "sufixo antes de .tar.gz"
verificar "$raiz/engine/Makefile_old"              deny  "sem extensao nenhuma"

echo "== deve PERMITIR: o padrao e prefixo de outra palavra =="
verificar "$raiz/mcp/tests/test_finalize.py"       allow "_final dentro de _finalize"
verificar "$raiz/docs/test_copyright.md"           allow "_copy dentro de _copyright"
verificar "$raiz/docs/parser_newline.md"           allow "_new dentro de _newline"
verificar "$raiz/mcp/tests/test_new_user.py"       allow "_new no meio, nao no fim"
verificar "$raiz/mcp/tests/test_older_api.py"      allow "_old dentro de _older"

echo "== deve BLOQUEAR: caixa nao e bypass (NTFS trata como o mesmo arquivo) =="
verificar "$raiz/mcp/src/genuino_mcp/server_V2.py" deny  "_V2 maiusculo"
verificar "$raiz/docs/server_Copy.md"              deny  "_Copy capitalizado"
verificar "$raiz/docs/plano_FINAL.md"              deny  "_FINAL caixa alta"
verificar "$raiz/dados_BACKUP.json"                deny  "_BACKUP caixa alta"
verificar "$raiz/engine/motor_Old.ps1"             deny  "_Old capitalizado"
verificar "$raiz/mcp/conf_New.json"                deny  "_New capitalizado"

echo "== deve PERMITIR: a fronteira sobrevive a caixa =="
verificar "$raiz/mcp/tests/test_FINALIZE.py"       allow "_FINAL dentro de _FINALIZE"
verificar "$raiz/docs/test_COPYRIGHT.md"           allow "_COPY dentro de _COPYRIGHT"
verificar "$raiz/docs/parser_NEWLINE.md"           allow "_NEW dentro de _NEWLINE"

echo "== deve PERMITIR: escrita legitima =="
verificar "$raiz/mcp/src/genuino_mcp/server.py"    allow "nome normal"
verificar "$raiz/CLAUDE.md"                        allow "arquivo existente"

echo "== deve PERMITIR: arquivo que JA existe (edicao de legado) =="
legado="$raiz/runs/.legado_old.txt"
: > "$legado"
verificar "$legado"                                allow "existe: editar nao e copiar"
rm -f "$legado"
verificar "$legado"                                deny  "mesmo nome, agora inexistente"

echo
if [ "$falhas" -eq 0 ]; then
    echo "ORACULO VERDE: $total/$total casos."
    exit 0
fi
echo "ORACULO VERMELHO: $falhas de $total casos reprovados." >&2
exit 1
