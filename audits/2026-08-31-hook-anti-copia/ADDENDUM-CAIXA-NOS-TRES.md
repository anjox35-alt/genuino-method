# Addendum — a regra de caixa aplicada nos tres hooks

Data: 2026-08-31. Autor: gerente. GO explicito do autor para os dois restantes.

Nao reescreve nenhum recibo anterior. Os dois continuam validos no que mediram.

| recibo | sha256 |
|---|---|
| `audits/2026-08-31-hook-anti-copia/AUDITORIA.md` | `b5d8e809c250f203bc1716cc92dca79bbffab244a6411c36ffa440ca48f5b082` |
| `audits/2026-08-31-hook-anti-copia/ADDENDUM-CAIXA.md` | `c8487f6b52e3b81c52f9e38ead3bc7f1ca828249f50690c83b63f12b2b0e28cb` |

`ADDENDUM-CAIXA.md` encerrava dizendo que `proteger-oraculo.sh` estava "nao
tocado, aguardando GO". Era verdade quando foi escrito. Este addendum registra
o que veio depois.

---

## 1. Enquadramento

Nao sao tres bugs. E **uma regra faltando, aplicada em tres lugares**: a
comparacao de caminho tem de seguir a semantica de caixa do filesystem em que
roda. O NTFS nao distingue caixa, e os tres hooks comparavam distinguindo.

Medido antes de qualquer conserto, glob puro de shell, sem efeito colateral:

```
NO      */mcp/tests/*  <-  D:/r/mcp/Tests/t.py
NO      */mcp/tests/*  <-  D:/r/MCP/TESTS/t.py
NO      */mcp/*.py     <-  D:/r/MCP/src/a.py
NO      */mcp/*.py     <-  D:/r/mcp/src/a.PY
```

## 2. DECISAO — minimo, e por que ficaram tres implementacoes

O autor escolheu, entre tres opcoes apresentadas: **acrescentar `| tr 'A-Z'
'a-z'` ao pipeline `normalizado` que ja existia nos dois hooks de shell**. Sem
helper compartilhado, sem unificacao em Python.

A justificativa, que o autor pediu declarada:

Um helper de shell unificaria **2 dos 3**, nao os tres. `impedir-copia.sh`
normaliza dentro do proprio `python`, e nao usaria um `.sh` sourceado. O ganho
seria ir de tres lugares para dois, em troca de uma dependencia de `source` no
caminho critico de todo `Write` e `Edit` da sessao: se o `.` falhar, o hook
quebra em toda escrita, nao numa.

A unificacao completa em Python existe e resolveria de verdade, mas e reescrita
de dois hooks que funcionam — um deles guardando integridade de missao — dentro
de um conserto de um token. Escopo maior que o defeito.

A regra fica dita em duas linguagens porque os tres casam coisas diferentes:
fronteira de sufixo por regex num caso, glob de diretorio nos outros dois.

## 3. `proteger-oraculo.sh` — o grave

Oraculo novo: `.claude/hooks/test-proteger-oraculo.sh`, 9 casos, cobrindo os
dois ramos do hook, com e sem missao ativa.

Duas salvaguardas no teste, porque uma sentinela esquecida bloqueia escrita em
`mcp/tests/` ate alguem descobrir por que: aborta com exit 2 se ja existir
missao real, e `trap ... EXIT INT TERM` remove mesmo se um caso falhar no meio.

```
RED    2 de 9 reprovados, EXIT=1     (mcp/Tests/, MCP/TESTS/)
GREEN  9/9,               EXIT=0
```

O caso que mais importa nao e de caixa: **sem missao ativa, escrever no oraculo
continua permitido**. E o passo 1 do fluxo R7, e sem esse caso o conserto podia
ter virado bloqueio permanente do proprio oraculo.

**Defeito do harness, corrigido antes do conserto.** A primeira versao do teste
encanava `python` direto no hook. Sem missao ativa o hook faz `exit 0` sem ler
stdin, e o produtor morria com `OSError: [Errno 22]` ao dar flush num pipe
fechado. O veredito estava certo, o ruido nao: um oraculo que grita sozinho
perde autoridade, e ruido em teste se le como defeito do construto. Passou a
montar o json numa variavel antes de alimentar o hook. Mesmo veredito, 2 de 9,
sem ruido.

## 4. `formatar-python.sh` — o leve

Oraculo novo: `.claude/hooks/test-formatar-python.sh`, 10 casos.

O ramo de match roda `uv run ... ruff format`, que escreve em arquivo e paga
segundos de startup. Medir a decisao sem pagar isso e **sem por seam no codigo
de producao**: um `uv` falso no inicio do `PATH`, registrando os argumentos
recebidos. Testa o construto real, nao uma copia da logica dele.

O plano previa `GENUINO_HOOK_DRY_RUN` como reserva, caso um executavel sem
extensao nao rodasse sob o `sh` do Git Bash. **Nao foi preciso**: o stub
executa, e o oraculo abre com uma guarda que sai com exit 2 se ele nao executar
— um stub silencioso reprovaria todo caso de "formata" e acusaria o hook por um
defeito do teste.

```
RED    3 de 10 reprovados, EXIT=1    (MCP/src/a.py, mcp/src/a.PY, mcp/tests/A.PY)
GREEN  10/10,              EXIT=0
```

## 5. A invariante que nao podia quebrar

Minusculizar **so a copia de comparacao**. `$alvo` original continua sendo o que
vai para o `ruff format` e para as mensagens. Num filesystem que distingue
caixa, o caminho minusculizado nao existe, e passa-lo ao ruff formataria o
arquivo errado ou nenhum.

Verificado no diff, e nao por leitura: a linha que invoca o ruff nao aparece
entre as alteradas, e a linha que monta o `permissionDecision` do outro hook
tem zero alteracoes.

## 6. Regressao

```
sh .claude/hooks/test-impedir-copia.sh      EXIT=0   (28/28, nao regrediu)
sh .claude/hooks/test-proteger-oraculo.sh   EXIT=0   (9/9)
sh .claude/hooks/test-formatar-python.sh    EXIT=0   (10/10)
```

Nenhuma sentinela sobrou no disco depois das rodadas. Os seis arquivos de
`.claude/hooks/` estao em ASCII puro, como os dois originais ja eram.

## 7. Limites declarados

- **Premissa de filesystem.** Os tres hooks agora assumem FS insensivel a
  caixa. Vale porque rodam na sessao do autor, no Windows. Rodar Claude Code em
  Linux invalida a premissa: la `MCP/TESTS` e de fato outro diretorio, e
  minusculizar passaria a casar caminho que nao devia.
- **Os oraculos nao rodam na CI.** So Pester e pytest rodam. Deixado assim de
  proposito: a matriz ubuntu distingue caixa, e os casos de caixa estariam
  errados la. Levar para a CI exige o mesmo tratamento condicional que
  `docs/limites.md:313` descreve, invertido — la o caso e pulado no NTFS e
  rodado no ubuntu; aqui seria o contrario.
- **`impedir-copia.sh` falha aberto**, como ja declarado no recibo anterior.

## 8. Observado, nao corrigido

`proteger-oraculo.sh` interpola `$missao`, lido de arquivo, dentro de codigo
Python montado por string de shell. Um id de missao com aspa ou quebra de linha
quebra o hook. Pre-existente, nao e defeito de caixa, e nao foi tocado — nao ha
GO para ele.

## 9. Write set

```
.claude/hooks/proteger-oraculo.sh          M  +1 pipe, +comentario
.claude/hooks/formatar-python.sh           M  +1 pipe, +comentario
.claude/hooks/test-proteger-oraculo.sh     +  oraculo, 9 casos
.claude/hooks/test-formatar-python.sh      +  oraculo, 10 casos
audits/.../ADDENDUM-CAIXA-NOS-TRES.md      +  este recibo
docs/limites.md                            M  1 linha na tabela
```

Nada em `mcp/`, `engine/`, `.github/`, `method/` ou `nucleo/`.
