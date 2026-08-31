---
name: auditar-oraculo
description: Manda missao e oraculo ao contra-auditor independente antes de delegar ao operario, e mostra o veredito com os achados. Use depois de escrever ou alterar qualquer teste de aceitacao, e antes de rodar o green loop.
---

# Contra-auditoria do oraculo

Roda `engine/Invoke-Auditor.ps1` sobre a missao e o teste de aceitacao, antes de
o operario existir na historia.

## Por que esta skill existe

O limite 1 de `docs/limites.md`: a separacao autor/juiz vale para o operario e
nao vale para o gerente. Quem escreve o oraculo e o gerente, e se o teste for
insuficiente o motor o executa numa arvore limpa, obtem exit 0 e grava `GREEN`
com toda a aparencia de rigor.

Aconteceu de verdade em `642f710`: a assercao era `!= 0`, que passa numa arvore
sem `.semgrep/rules` porque o gate ja sai com 2 sem consultar o selo uma vez. O
operario trabalhou contra um oraculo que nao provava o que dizia provar, e o
GREEN foi legitimo aos olhos do motor.

Na missao seguinte o auditor recebeu o oraculo antes e devolveu `INSUFICIENTE`
duas vezes seguidas, ambas com razao.

## Procedimento

1. **Monte o material.** Missao e oraculo, na integra:

   ```bash
   { echo "===== MISSAO ====="; cat missions/<id>.md
     echo; echo "===== ORACULO ====="; cat mcp/tests/<arquivo>.py
   } > material.txt
   ```

   Mandar so a missao produz uma auditoria sobre a promessa, nao sobre a regua.
   Na primeira execucao sobre a `nucleo-01` eu esqueci o oraculo, e o auditor
   declarou exatamente isso como limite: nao podia dizer o que era medido,
   apenas que o gate reportou exit 0.

2. **Rode:**

   ```bash
   pwsh -File engine/Invoke-Auditor.ps1 < material.txt
   ```

   Precisa de `NVIDIA_API_KEY` no ambiente. Sem ela o script sai com 2 -- nao
   medir nao e aprovar, e o loop nao deve parar por falta de auditor externo.

3. **Leia o exit code, nao a prosa:**

   | Exit | Significado | O que fazer |
   |---|---|---|
   | 0 | Veredito sustentado | Pode delegar. Leia os `findings` mesmo assim |
   | 1 | Refutado | NAO delegue. Corrija o oraculo e rode de novo |
   | 2 | Nao foi possivel medir | Servico fora, chave ausente ou resposta truncada. Registre como `NOT_VERIFIED` |

4. **Trate `observed: true` e `observed: false` de forma diferente.** Achado
   observado tem evidencia no material. Hipotese nao refuta nada sozinha -- mas
   tambem nao se apaga: vira caso de teste ou limite declarado.

5. **Corrija o oraculo, nao a implementacao.** Nesta etapa nao existe
   implementacao. Se a vontade for consertar codigo, a etapa errada esta sendo
   executada.

6. **Guarde o veredito** em `audits/<data>-oraculo-<id>/`, com as rodadas. Uma
   auditoria que so existiu no terminal nao e evidencia de nada.

## Limites desta auditoria

- **O prompt do auditor e escrito pelo gerente.** Quem formula a pergunta limita
  as respostas possiveis. O limite 1 reaparece um degrau acima, menor, nao
  eliminado.
- **O auditor nao executa nada.** Le missao e oraculo e raciocina sobre
  mutantes. Nenhum achado dele foi verificado por execucao.
- **Um modelo que erra diferente ainda erra.** Independencia de familia reduz
  modo de falha compartilhado; nao produz verdade.
- **O tier gratuito da NVIDIA e instavel.** Numa mesma sessao o mesmo modelo
  devolveu 200, 503 e 404. Por isso o script tenta uma lista de modelos antes
  de desistir.
