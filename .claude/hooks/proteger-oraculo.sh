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

# `python` nao existe de fabrica em Linux e macOS recentes: la o binario se
# chama `python3`. Sem resolver entre os dois, o hook cai em 127 nesses hosts
# e -- com a sentinela presente -- nega TODA escrita da sessao, nao so as de
# `mcp/tests/`. O repositorio e publico e a R7 manda o recem-chegado abrir
# missao antes de mexer, entao esse host e o caso comum, nao o exotico.
#
# Resolver amplia onde o hook consegue MEDIR, nunca onde ele libera: se
# nenhum dos dois existir, `${py:-python}` chama `python`, que sai 127 e cai
# no mesmo deny de sempre. A resolucao vem depois da sentinela de proposito
# -- fora de missao o hook nao decide nada, e nao deve pagar nem isso.
py=""
for candidato in python python3; do
    if command -v "$candidato" >/dev/null 2>&1; then
        py=$candidato
        break
    fi
done

# Duas saidas diferentes, de proposito. Exit != 0 significa que o evento nao
# pode ser lido -- nao medi. Exit 0 com saida vazia significa que o evento foi
# lido e simplesmente nao carrega caminho, como num Bash -- medi, e nao ha
# alvo. Colapsar as duas fazia "nao consegui" virar "pode escrever".
#
# O try cobre tambem o acesso (d.get, ti.get), nao so o json.load. Um payload
# JSON valido porem nao-objeto -- null, 42, [1,2] -- passava pelo json.load e
# so quebrava depois, no d.get(...), com AttributeError: Python leva isso a
# exit 1, nao ao exit 3 desenhado. O deny observavel saia igual, porque
# qualquer codigo != 0 cai no mesmo lugar abaixo -- mas era rede acidental,
# nao projetada. Medido.
#
# `notebook_path` entra na cadeia porque o matcher em `.claude/settings.json`
# inclui `NotebookEdit`, e essa ferramenta nao manda `file_path`. Sem a
# clausula, um notebook sob `mcp/tests/` produzia alvo vazio, o `[ -n ... ]`
# abaixo lia isso como "evento sem caminho" e o hook LIBERAVA a escrita com
# missao em curso. O irmao `impedir-copia.sh` ja lia os tres campos; este lia
# dois, e a diferenca nao era decisao, era descuido.
#
# O extrator devolve a FORMA DE COMPARACAO, nao o caminho cru. A normalizacao
# vivia depois dele, num pipeline de dois `tr` cujo exit code o shell
# descartava: faltando um dos binarios, a variavel saia vazia, o `case` abaixo
# nao casava, e o hook liberava a escrita COM missao em curso -- o mesmo ALLOW
# silencioso que o paragrafo acima fecha, reaberto vinte linhas depois por um
# comando externo sem guarda. Aqui dentro a normalizacao passa a viver sob a
# guarda que ja existe: se ela falhar, o `except` leva ao exit 3, e qualquer
# codigo != 0 nega.
#
# `posixpath` e nao `os.path`: no Windows o `os.path.normpath` reintroduz a
# barra invertida que o `replace` acabou de tirar.
#
# `normpath` colapsa `//`, `.` e `..` porque o filesystem tambem colapsa.
# `mcp//tests/x.py`, `mcp/./tests/x.py` e `mcp/src/../tests/x.py` nomeiam o
# MESMO arquivo em disco que `mcp/tests/x.py`, e os tres passavam pelo `case`.
# Vale nos dois sentidos: `mcp/tests/../src/x.py` deixa de ser tratado como
# oraculo, porque nao e um.
#
# E minusculas porque o NTFS nao distingue caixa: `mcp/Tests/t.py` E
# `mcp/tests/t.py`, o mesmo arquivo. Sem isso o `case` abaixo e sensivel a
# caixa, e a protecao do oraculo cai com a tecla shift. Medido antes do
# conserto, sob missao ativa: `mcp/Tests/` e `MCP/TESTS/` passavam.
#
# O guarda `if alvo` existe porque `posixpath.normpath("")` devolve `"."`.
# Sem ele, um evento que nao carrega caminho nenhum -- um Bash, por exemplo --
# passaria a imprimir um alvo que nao existe, e o `[ -n ... ]` abaixo perderia
# a distincao entre "sem alvo" e "com alvo" que o paragrafo acima construiu.
#
# So a forma de comparacao e impressa porque este hook nao escreve em disco
# nem repassa o alvo a ninguem: ele decide, e mais nada. O irmao
# `formatar-python.sh` entrega o arquivo ao ruff, entao la o caminho original
# continua sendo o que importa.
normalizado=$("${py:-python}" -c '
import json, posixpath, sys
try:
    d = json.load(sys.stdin)
    ti = d.get("tool_input") or {}
    alvo = ti.get("file_path") or ti.get("path") or ti.get("notebook_path") or ""
    if alvo:
        alvo = posixpath.normpath(alvo.replace("\\", "/")).lower()
except Exception:
    sys.exit(3)
print(alvo)
' 2>/dev/null)
codigo=$?

if [ "$codigo" -ne 0 ]; then
    # Ha missao ativa e o hook nao conseguiu nem descobrir o alvo. Interpretador
    # ausente cai aqui tambem, com 127. Nao medir nao e aprovar.
    cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Oraculo protegido: ha missao em curso e o hook nao conseguiu ler o evento para descobrir o alvo da escrita. Nao medir nao e aprovar. Se a escrita for legitima, encerre a missao removendo runs/.missao-ativa."}}
JSON
    exit 0
fi

[ -n "$normalizado" ] || exit 0

# O segundo padrao nao e redundante: o `normpath` remove o `./` inicial, entao
# um evento com `./mcp/tests/x.py` chega aqui como `mcp/tests/x.py`, sem a
# barra que o primeiro padrao exige. Sem ele, a normalizacao LIBERARIA um
# caminho que o hook negava antes dela -- uma protecao trocada por outra nao
# e conserto. Caminho relativo resolve contra o diretorio de trabalho de quem
# escreve; se for a raiz do projeto, `mcp/tests/x.py` E o oraculo. Este hook
# fecha na duvida, que e a doutrina dele desde o inicio. `xmcp/tests/x.py`
# continua fora, porque o padrao do `case` casa a string inteira, nao um
# pedaco dela.
case "$normalizado" in
    */mcp/tests/*|mcp/tests/*)
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
        saida=$("${py:-python}" -c '
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
