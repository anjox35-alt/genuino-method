# Addendum — o hook anti-copias nao tratava caixa

Data: 2026-08-31. Autor: gerente. Achado por revisao humana.

Este addendum **nao reescreve** `AUDITORIA.md`. Aquele arquivo e recibo de
execucoes que aconteceram, e continua valido no que mediu. Corrige-se aqui.

Recibo corrigido: `audits/2026-08-31-hook-anti-copia/AUDITORIA.md`
sha256: `b5d8e809c250f203bc1716cc92dca79bbffab244a6411c36ffa440ca48f5b082`

---

## 1. O que estava errado

A secao 6 daquele recibo, "Limites conhecidos", listava tres limites e **nao
listava caixa**. O hook casava o padrao com `re.search` sensivel a caixa,
entao a tecla shift era bypass completo.

Medido antes do conserto:

```
ALLOW  server_V2.py
ALLOW  server_Copy.md
ALLOW  plano_FINAL.md
ALLOW  dados_BACKUP.json
ALLOW  motor_Old.ps1
ALLOW  conf_New.json
deny   notas (1).MD      <- negava porque aquele padrao nao tem letra
deny   server_v2.py
```

O `19/19` do recibo original era verdadeiro: aquele oraculo passava mesmo. Ele
era **incompleto**, nao falso. Nenhum dos 19 casos variava a caixa, entao o
GREEN nao cobria a unica coisa que separava o hook de ser contornavel por uma
tecla.

## 2. Por que isso e bypass e nao detalhe cosmetico

O NTFS nao distingue caixa. Medido:

```
$ : > server_v2.py && [ -e server_V2.py ] && echo mesmo-arquivo
mesmo-arquivo
```

`server_V2.py` nao e um arquivo parecido com `server_v2.py`. E o mesmo
arquivo. Um matcher sensivel a caixa nao esta sendo mais restrito: esta apenas
deixando passar a copia que ele existe para impedir.

## 3. O precedente, e onde ele difere

`docs/limites.md:313` ja registra caixa mordendo esta base: `-notcontains`
era case-insensitive e um `src/foo` permitido apagava um `SRC/FOO` externo da
lista de violacoes. O conserto foi `-cnotcontains`, isto e, tornar a comparacao
**sensivel**.

A direcao ali e o oposto da daqui, e vale dizer em voz alta para que ninguem
copie a solucao errada de um caso para o outro. La o filesystem distinguia caixa
e a comparacao nao; aqui o filesystem nao distingue e a comparacao distinguia.
O principio e o mesmo nos dois: **a comparacao tem de seguir a semantica do
filesystem**, e errar em qualquer das direcoes produz um gate que nao mede o que
diz medir.

## 4. RED e GREEN

Nove casos novos no oraculo, seis de `deny` em caixa alta e tres de `allow`
para provar que a fronteira sobrevive.

```
RED    sh .claude/hooks/test-impedir-copia.sh  ->  6 de 28 reprovados, EXIT=1
GREEN  sh .claude/hooks/test-impedir-copia.sh  ->  28/28,              EXIT=0
```

Prova ponta a ponta pela ferramenta `Write` real, na sessao viva:

| alvo | resultado |
|---|---|
| `prova_FINAL.md` | negado, razao citando `_FINAL` |
| `teste_FINALIZE.md` | criado normalmente |

O segundo caso e o risco que a propria correcao introduz: tornar o match
insensivel podia passar a reprovar `_FINALIZE`, `_COPYRIGHT` e `_NEWLINE`.
Nao passou.

## 5. DECISAO — `re.IGNORECASE`, nao `nome.lower()`

A revisao pediu normalizacao para minusculas. Implementei com a flag, por dois
motivos concretos:

1. `str.lower()` muda o comprimento em alguns pontos Unicode — o I maiusculo
   com ponto do turco, U+0130, vira dois caracteres — e ai o span da captura
   deixa de mapear no nome original.
2. `group(1)` preserva a caixa como digitada. A razao do deny diz `_FINAL`,
   que foi o que o operador escreveu. Com `.lower()` diria `_final`, e um
   bloqueio que cita um nome diferente do digitado parece defeito do gate.

O efeito observavel pedido — caixa nao e bypass — esta entregue e medido.

## 6. Achado colateral, NAO corrigido

`proteger-oraculo.sh` tem o mesmo defeito de classe. O `case` do shell e
sensivel a caixa. Medido com a sentinela ativa, depois removida:

```
deny   D:/r/mcp/tests/test_x.py
ALLOW  D:/r/mcp/Tests/test_x.py
ALLOW  D:/r/MCP/TESTS/test_x.py
```

E mais grave que o defeito deste addendum: significa que o oraculo de uma missao
em curso pode ser editado por uma variante de caixa, que e exatamente a
integridade que aquele hook existe para proteger. Fora do escopo pedido nesta
revisao. Nao tocado, aguardando GO.

## 7. Write set deste addendum

```
.claude/hooks/impedir-copia.sh        (IGNORECASE + comentario; ASCII restaurado)
.claude/hooks/test-impedir-copia.sh   (+9 casos)
audits/.../ADDENDUM-CAIXA.md          (este arquivo)
```

`AUDITORIA.md` intacto. Nada commitado, nada empurrado.
