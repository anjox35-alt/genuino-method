# Auditoria do oraculo — check-bloat-chave-em-string

Tres rodadas, duas leituras independentes por rodada, antes de o operario ver a
missao. Nenhuma rodada sustentou de primeira, e as tres acharam defeito real no
oraculo do gerente.

| Rodada | Antigravity (gemini-3.1-pro-high) | Codex (`--sandbox read-only`) |
|---|---|---|
| 1 | `exit 1` REFUTADO — 3 achados | `exit 0` — 4 mutantes + o falso-verde do teste-guarda |
| 2 | `exit 1` REFUTADO — 3 achados de cobertura | `exit 0` — os 4 mutantes mortos; 2 novos materiais |
| 3 | `exit 1` REFUTADO — chave isolada permite replace do literal | timeout de 10 min, **sem veredito** |

## O que cada rodada mudou no oraculo

**Rodada 1.** O teste-guarda `test_correcao_da_chave_em_string_nao_cega_o_gate`
ficava verde **sem provar nada**: a contagem estourava, caia no
`return len(lines)`, e como o arquivo terminava junto com a funcao o resultado
ainda passava do teto. O gerente escreveu um guarda que nao guardava.
Correcao: passar a medir o COMPRIMENTO reportado, e nao apenas a presenca do
achado.

**Rodada 2.** Dois mutantes novos, ambos observados:
`return index` em vez de `return index + 1` sobrevivia porque o assert era a
faixa `< 100`; e um sanitizador unilateral que ignora `{` em literal mas conta
`}` em literal passava porque nenhuma fixture tinha `}` entre aspas.
Correcao: igualdade exata derivada da fixture, e `}` em string no meio do corpo.

**Rodada 3.** As chaves das fixtures eram **isoladas** (`'{'`), entao um
`line.replace("'{'", "")` passaria — exatamente o atalho que a missao proibe nas
STOP CONDITIONS. Correcao: toda chave passou a vir grudada em texto
(`'json quebrado: {'`).

## Recusas do gerente, e o motivo

Duas, ambas declaradas ao auditor na rodada seguinte para poderem ser contestadas:

- **Template literals com crase, strings multilinha, here-strings, aspas
  escapadas** (Antigravity, rodada 2). Estado de string multilinha nao e
  resolvivel por heuristica linha a linha, e a missao declara que parser de
  linguagem inteiro e inflacao. Vira limite declarado e missao candidata.
- **Campo numerico tipado em `Finding`** para eliminar o acoplamento ao texto do
  `excerpt` (Codex, rodada 2). `core.py` esta fora do write-set desta missao.
  Candidata separada. O limite ficou registrado no docstring do helper.

## Decisao

Delegar apos a rodada 3, sem quarta rodada. O motivo nao e cansaco: o proprio
loop roda contra-auditoria antes de gravar GREEN, e pre-auditar sem fim anula a
razao de existir aquela etapa. A decisao foi levada ao autor e aprovada por ele.

## Limites desta auditoria

- O prompt dos dois revisores foi escrito pelo gerente. O limite 1 de
  `docs/limites.md` reaparece um degrau acima, menor, nao eliminado.
- Nenhum dos dois executou nada. Os mutantes sao tracados estaticamente.
- Codex operario e Codex revisor sao o mesmo modelo em permissoes diferentes:
  contra-leitura, nao confirmacao independente.
- A rodada 3 nao tem veredito do Codex. O timeout de 10 minutos e falha de
  medicao, nao aprovacao.

---

## Vereditos integrais do Antigravity

### Rodada 1

```json
{
  "backend": "agy",
  "auditor": "gemini-3.1-pro-high",
  "verdict": "REFUTADO",
  "questions": [
    "A implementação apresentada soluciona o problema para chaves de fechamento ('}') e aspas duplas, cumprindo a exigência de funcionar em strings literais de forma genérica, dado que o oráculo mede apenas uma chave de abertura em aspas simples?",
    "A solução rejeita a abordagem de mascarar ou substituir especificamente a string exata \"'{'\", que passaria nos testes atuais mas violaria a proibição explícita da missão de criar um caso especial para a sequência do defeito?",
    "A correção mantém o balanceamento de chaves correto para JavaScript e TypeScript, considerando que o oráculo fornecido avalia a correção exclusivamente usando scripts PowerShell (.ps1)?"
  ],
  "findings": [
    {
      "observed": true,
      "severity": "alto",
      "what": "O oráculo testa exclusivamente a presença da chave de abertura ('{') delimitada por aspas simples, deixando aspas duplas e chaves de fechamento ('}') completamente sem cobertura de teste."
    },
    {
      "observed": true,
      "severity": "alto",
      "what": "Os testes passariam com uma implementação incorreta e plausível que subtraísse apenas a sequência exata \"'{'\" da linha antes da contagem, o que permite burlar a proibição de caso especial mantendo o veredito GREEN."
    },
    {
      "observed": true,
      "severity": "medio",
      "what": "A missão exige suporte a 'qualquer das linguagens que o gate mede', mas os testes de aceitação relacionados às chaves em strings atuam somente sobre a extensão .ps1, ignorando validações em JS e TS."
    }
  ],
  "limits": [
    "Não é possível afirmar o que o patch implementado de fato fez, pois o código da alteração real não foi fornecido.",
    "Não é possível determinar se o gate também possui falhas com chaves comentadas ou dentro de strings com interpolação, pois o material foca exclusivamente no caso das strings literais puras."
  ]
}

```

### Rodada 2

```json
{
  "backend": "agy",
  "auditor": "gemini-3.1-pro-high",
  "verdict": "REFUTADO",
  "questions": [
    "A missão exige que a correção funcione para 'qualquer das linguagens que o gate mede' (incluindo JS e TS). Se a implementação tratar apenas aspas simples e duplas, ignorando literais de template (crases/backticks `), qual teste impedirá que esse falso GREEN seja integrado?",
    "Se a implementação varrer o texto linha a linha e não acompanhar o estado de strings multilinhas (como here-strings no PowerShell ou literais de template no JS), uma chave solta em uma nova linha quebrará a contagem. Algum teste atual captura isso?",
    "Se a string contiver caracteres de escape antes de uma chave, uma heurística ingênua baseada em particionamento simples falhará. Onde o oráculo testa a resiliência contra aspas escapadas dentro da string literal?"
  ],
  "findings": [
    {
      "observed": true,
      "severity": "alto",
      "what": "Falta de cobertura para JS/TS: Os testes recém-adicionados criam apenas scripts .ps1 e testam unicamente aspas simples e duplas, omitindo a sintaxe de literais de template (`) essencial para garantir que o gate não quebre em JS e TS."
    },
    {
      "observed": true,
      "severity": "medio",
      "what": "Falta de cobertura para strings multilinhas: O oráculo avalia chaves apenas dentro de strings de linha única, permitindo que implementações frágeis processem o texto linha a linha e quebrem a contagem em blocos multilinhas."
    },
    {
      "observed": true,
      "severity": "medio",
      "what": "Falta de cobertura para aspas escapadas: Não há fixtures que exercitem a presença de escapes dentro de uma string literal, o que permitiria a aprovação de parsers ou expressões regulares vulneráveis a esses caracteres."
    }
  ],
  "limits": [
    "Não posso afirmar a técnica exata usada pela implementação para alcançar o GREEN (e.g., regex, máquina de estados isolada), apenas que o oráculo possui furos de cobertura que aprovariam abordagens incorretas.",
    "Não avaliei se o gate também quebra com chaves inseridas dentro de comentários, visto que a missão delimitou o escopo rigorosamente a 'string literal'."
  ]
}

```

### Rodada 3

```json
{
  "backend": "agy",
  "auditor": "gemini-3.1-pro-high",
  "verdict": "REFUTADO",
  "questions": [
    "O oráculo impede que uma implementação sobreajustada limpe apenas literais idênticos aos do defeito original (ex: '{', \"{\") em vez de processar chaves dentro de qualquer string?",
    "A missão exige que a regra não seja um caso especial para PowerShell, mas o oráculo comprova que a correção funciona para outras linguagens com chaves (JS, TS)?"
  ],
  "findings": [
    {
      "observed": true,
      "severity": "alto",
      "what": "As fixtures dos dois novos testes utilizam apenas chaves isoladas dentro das aspas (ex: '{', \"{\", '}'). Uma implementação errada e frágil que simplesmente faça `line = line.replace(\"'{'\", \"\").replace('\"{\"', \"\")` passará no oráculo, mas continuará falhando no mundo real quando a chave estiver misturada a texto (ex: `Write-Output \"json quebrado: {\"`)."
    },
    {
      "observed": true,
      "severity": "medio",
      "what": "Os testes de aceitação adicionados criam exclusivamente arquivos `.ps1`. Não há cobertura para comprovar que a solução atende JavaScript e TypeScript, o que permite que uma implementação adicione `if rel.endswith('.ps1')` (modificando a assinatura) e passe despercebida, violando a restrição explícita da missão."
    }
  ],
  "limits": [
    "Não posso afirmar qual técnica o implementador usaria (ex: regex vs. replace textual ingênuo), mas o contrato atual não tem força estrutural para vetar atalhos textuais que sobreajustam ao defeito original."
  ]
}

```

