# Addendum — o que a178e05 e 140ba87 corrigiram na interpolacao do oraculo

Data: 2026-09-01. Autor: gerente (Claude Code), trabalho direto. Hooks em
`.claude/**` sao kernel de governanca pela R1: nunca delegados ao operario.

Nao reescreve nenhum recibo anterior. Os tres continuam validos no que
mediram.

| recibo | sha256 |
|---|---|
| `audits/2026-08-31-hook-anti-copia/AUDITORIA.md` | `b5d8e809c250f203bc1716cc92dca79bbffab244a6411c36ffa440ca48f5b082` |
| `audits/2026-08-31-hook-anti-copia/ADDENDUM-CAIXA.md` | `c8487f6b52e3b81c52f9e38ead3bc7f1ca828249f50690c83b63f12b2b0e28cb` |
| `audits/2026-08-31-hook-anti-copia/ADDENDUM-CAIXA-NOS-TRES.md` | `27784ea5670f05a2d21a6c6177a2a2b5c13c8786fdfebad0115962e6203b3a37` |

`ADDENDUM-CAIXA-NOS-TRES.md` encerra, na secao 8, dizendo que
`proteger-oraculo.sh` interpola `$missao` dentro de codigo Python montado por
string de shell, que um id de missao com aspa ou quebra de linha quebra o
hook, e que isso ficou observado e nao corrigido, sem GO para o conserto. Era
verdade quando foi escrito. Este addendum registra o que veio depois: dois
commits que fecham esse buraco. `a178e05` fecha a montagem da resposta de
deny; `140ba87` fecha a leitura do evento que antecede essa montagem.

---

## 1. O defeito, medido antes de qualquer conserto

Sentinela temporaria criada e removida a cada linha; alvo sempre
`mcp/tests/test_x.py`.

| id da missao | resultado | exit |
|---|---|---|
| `missao-normal` | deny correto | 0 |
| `missao com 'aspa'` | quebrou, `File "<string>", line 8` | 0 |
| duas linhas | quebrou, SyntaxError | 0 |
| `missao-com-barra\` | deny correto | 0 |
| `missao-}-solta` | deny correto | 0 |

O dano nao e injecao: e o **exit 0 sem deny**. A protecao do oraculo sumia em
silencio com missao em curso. O backslash final nao quebra porque cai antes
de um `"`, nao de um `'`.

## 2. DECISAO — fechar em dois pontos, por construcao, e por que diverge do `impedir-copia.sh`

Dois pontos de fechamento, um por task:

- **Task 1, montagem do deny.** Aspas simples no `-c`: o shell nao expande
  nada dentro da fonte, que deixa de ser template e passa a ser codigo
  literal. O id de missao entra por `sys.argv`, que python le como dado,
  nunca como sintaxe a interpretar. A saida do python so e usada quando
  contem de fato um `deny`; qualquer outra coisa — vazio, erro, saida parcial
  — cai num JSON literal montado pelo proprio shell.
- **Task 2, leitura do evento.** O extrator sai com `3` quando nao consegue
  ler o evento — falha do `json.load` —, e mantem exit 0 com saida vazia so
  quando o evento carrega mesmo nenhum caminho. Qualquer codigo != 0, 127 de
  interpretador ausente incluido, faz o shell emitir o mesmo deny fixo.

Os dois fecham **por construcao**, nao por confianca no exit code de um
interpretador que pode nem ter rodado: a decisao de negar nasce do que o
shell consegue verificar na propria saida, nao da suposicao de que o python
correu como esperado.

Isso diverge de proposito do irmao `impedir-copia.sh`, que falha aberto: a R4
declara que a propria regra "vale mesmo se o hook falhar", ou seja, nao
depende do hook para existir. A R1 nao declara nada equivalente sobre a
integridade do oraculo — nenhuma regra escrita garante essa protecao sem este
hook. Falhar aberto aqui apagaria a protecao exatamente no momento em que ela
e mais necessaria: sob missao em curso.

## 3. Task 1 — commit `a178e05` — RED e GREEN

```
RED    exit 1, 2 de 15 reprovados (`aspa simples`, `duas linhas`)
GREEN  exit 0, 15/15
GREEN  exit 0, 16/16  (com o caso novo: python quebrado so na montagem do deny)
```

**Correcao ao corpo do commit.** O corpo de `a178e05` diz "a `python` stub
that exits 1". Impreciso: nao e um stub que falha para qualquer chamada. O
stub coloca um executavel `python` na frente do `PATH` — sombreando o
interpretador real, resolvido antes via `command -v python`, sem remove-lo —
que conta os argumentos recebidos e so falha quando sao tres ou mais:

```sh
#!/bin/sh
if [ "$#" -ge 3 ]; then exit 1; fi
exec "$real" "$@"
```

A chamada que **extrai o alvo** do evento usa `python -c FONTE`, dois
argumentos, e cai no `exec` para o python real. A chamada que **monta o
deny** usa `python -c FONTE "$missao"`, tres argumentos, e e essa que o stub
intercepta. Um stub que falhasse para qualquer chamada teria matado a
extracao do alvo antes do bloco `case`, e o teste estaria medindo o extrator
da Task 2, nao a montagem da Task 1.

## 4. Task 2 — commit `140ba87` — RED e GREEN

```
RED    exit 1, 1 de 17 reprovado (evento ilegivel)
GREEN  exit 0, 17/17
```

Irmaos re-rodados sem alteracao, para regressao:

```
test-impedir-copia.sh    28/28
test-formatar-python.sh  10/10
```

Verificacao independente do gerente, fora do oraculo: **sem** sentinela —
sem missao ativa —, evento ilegivel devolve exit 0 e saida vazia, ou seja,
allow. O raio maior descrito no limite 3 abaixo so vale durante missao
ativa.

## 5. Limites que este addendum declara

1. O `try/except` do extrator cobre so a chamada a `json.load`. Um payload
   JSON valido mas nao-objeto — `null`, `42`, `[1,2]` — levanta
   `AttributeError` ao chamar `.get()` fora do bloco protegido, e sai 1, nao
   o `sys.exit(3)` desenhado para esse caso. O resultado observavel e
   identico: qualquer codigo != 0 chega ao mesmo deny. Mas a rede e
   acidental, nao projetada.
2. Nenhum teste dirige `python` ausente de verdade. O stub descrito na secao
   3 sombreia o interpretador no `PATH` em vez de remove-lo, entao o caminho
   command-not-found com codigo 127 nao e exercitado por nenhum oraculo. A
   logica de shell e identica para qualquer codigo != 0, e o caso de JSON
   malformado ja prova que o ramo dispara.
3. O raio da Task 2 e deliberadamente maior que o da Task 1: com missao
   aberta, um ambiente quebrado bloqueia **toda escrita**, nao so as de
   `mcp/tests/` — a checagem de exit code roda antes do `case` que restringe
   o alvo. Sem eufemismo: isso trava qualquer `Write` ou `Edit` da sessao
   inteira enquanto a sentinela existir. A saida e remover
   `runs/.missao-ativa`.
4. Divergencia deliberada do irmao `impedir-copia.sh`, que falha aberto,
   como fundamentado na secao 2: a R4 declara que aquela regra vale mesmo
   sem hook; a R1 nao declara nada equivalente sobre a integridade do
   oraculo.

## 6. Limite que continua aberto, sem mudanca aqui

A premissa de filesystem insensivel a caixa, ja declarada em
`ADDENDUM-CAIXA-NOS-TRES.md` secao 7, nao muda neste addendum: os tres hooks
continuam assumindo NTFS insensivel a caixa. Rodar a sessao em Linux
invalidaria a comparacao minusculizada la descrita. Este addendum mede
interpolacao, nao filesystem, e nao reabre esse limite.

## 7. Write set

```
.claude/hooks/proteger-oraculo.sh          M  a178e05 (montagem do deny) + 140ba87 (leitura do evento)
.claude/hooks/test-proteger-oraculo.sh     M  cresce de 9 casos (ADDENDUM-CAIXA-NOS-TRES.md sec. 3) para 17 (secao 4 acima)
audits/2026-08-31-hook-anti-copia/ADDENDUM-INTERPOLACAO.md   +  este recibo
```

Nada em `mcp/`, `engine/`, `.github/` ou `method/`. Este arquivo e commitado
nesta rodada; push nao acontece.
