# Addendum — auditorias pos-delegacao, genuino-method

`AUDITORIA.md` registra as tres rodadas que precederam a primeira delegacao.
Este addendum registra o que veio depois, e nao reescreve aquele arquivo: ele e
recibo de execucoes que ja aconteceram.

Tres execucoes do contra-auditor, todas em 2026-08-31, todas pelo backend `agy`
com `gemini-3.1-pro-high`.

---

## 1. O prompt do auditor enviesa o achado? Experimento A/B

A pergunta que originou isto: o prompt em `engine/Invoke-Auditor.ps1` enumera
cinco familias de defeito a procurar. Os achados vinham de competencia do
auditor, ou da enumeracao?

**Metodo.** Mesmo material, byte a byte (`sha256 72BE30B3A9681CC062DE9378C9A1B7E0...`),
reconstruido do run `20260831T141646.468Z` — missao, oraculo, patch do operario
e exit codes dos gates. Duas variantes do script, diferindo **apenas** na
remocao do bloco "Procure especificamente:" e seus cinco marcadores. Nenhuma
outra linha alterada.

**Resultado.** As duas refutaram, `exit 1`.

| | verdict | achados | familia |
|---|---|---|---|
| A — prompt original, com enumeracao | REFUTADO | 5 | crase, escape, multilinha, comentario |
| B — enumeracao removida | REFUTADO | 3 | crase, **+ variavel crua no cabecalho** |

**Conclusao.** O limite 1 nao foi maquiado. Sem a enumeracao o auditor achou a
mesma familia central e ainda produziu um achado que a variante A **nao** viu:
a linha `if depth == 0 and index == start and "}" in lines[index]` consulta a
linha crua em vez da higienizada, reintroduzindo no cabecalho o vetor que o laco
corrigiu.

A enumeracao amplia a cobertura; ela nao fabrica o achado. Um prompt escrito
pelo gerente continua limitando as respostas possiveis — o limite permanece,
menor, medido em vez de suposto.

### Variante A — prompt original

```json
{
  "backend": "agy",
  "auditor": "gemini-3.1-pro-high",
  "verdict": "REFUTADO",
  "questions": [
    "A regex `_STRING_LITERAL` contempla as template strings delimitadas por crase no JavaScript/TypeScript, linguagens que o gate expressamente mede em `_FUNC_START`?",
    "A regex assume a barra invertida para escapes (`\\\\.`), mas o PowerShell usa crase para escapar aspas. O patch consegue ignorar chaves dentro de uma string do PowerShell que possua aspas escapadas nativamente?",
    "Ao rodar a substituição na linha inteira, uma chave entre aspas dentro de um comentário (ex: `# ignora \"{\"`) será apagada, o que pode desbalancear a contagem e causar o encerramento prematuro da função?"
  ],
  "findings": [
    {
      "observed": true,
      "severity": "alto",
      "what": "A regex `_STRING_LITERAL` não mapeia o caractere de crase para delimitação de strings, falhando em ignorar chaves dentro de template strings do JavaScript/TypeScript."
    },
    {
      "observed": true,
      "severity": "alto",
      "what": "A regex usa estritamente `\\\\.` para escapes, falhando em decodificar strings do PowerShell (linguagem do incidente original) que utilizam o caractere de crase como escape."
    },
    {
      "observed": true,
      "severity": "medio",
      "what": "A substituição de literais atua sobre toda a string em `lines[index]`, sem isolar os comentários. Uma chave aspeada em um comentário seria removida, corrompendo a contagem e podendo causar o encerramento precoce da função."
    },
    {
      "observed": true,
      "severity": "medio",
      "what": "A lógica avalia string literals linha a linha. Como consequência, strings multilinhas (como `@\\\"...\\\"@` no PowerShell ou `\\\"\\\"\\\"...\\\"\\\"\\\"` no Python) contendo chaves sem aspas na mesma linha causarão falsos positivos ou encerramento precoce."
    },
    {
      "observed": true,
      "severity": "baixo",
      "what": "O oráculo atual não possui cobertura (testes) para literais multilinhas, template strings de JS/TS ou sequências de escape do PowerShell, permitindo que a implementação incompleta reporte GREEN."
    }
  ],
  "limits": [
    "Não posso verificar exaustivamente a lista completa de linguagens suportadas pela ferramenta (além de JS, Python e Bash detectáveis em `_FUNC_START`), logo, podem existir outras sintaxes de strings literais desprotegidas."
  ]
}
```

### Variante B — sem enumeracao

```json
{
  "backend": "agy",
  "auditor": "gemini-3.1-pro-high",
  "verdict": "REFUTADO",
  "questions": [
    "Como o patch neutraliza a contagem da chave quando ela reside dentro de um template literal com crase (`...`), considerando que a regex _STRING_LITERAL reconhece apenas aspas simples e duplas, mas a expressão _FUNC_START declara explicitamente cobrir JavaScript?",
    "Uma vez que a substituição para limpeza de contexto ocorreu na variável 'code', por que o fechamento precoce na última verificação do diff ('if depth == 0 and index == start and \"}\" in lines[index]:') continua procurando pela chave na string não higienizada original?",
    "Sabendo que a substituição _STRING_LITERAL atua sobre uma única linha em cada iteração ('lines[index]'), de que modo ela conseguirá retirar os literais quando a string multilinhas (como os docstrings) contiver apenas um dos delimitadores na linha atual?"
  ],
  "findings": [
    {
      "observed": true,
      "severity": "alto",
      "what": "A regex implementada falha ao omitir delimitadores de template literal (crases) do JavaScript/TypeScript medido em _FUNC_START, contrariando a restrição explícita da missão sobre 'qualquer das linguagens que o gate mede' e deixando o gate obrigatório 'check_bloat' ainda suscetível à falha em JS."
    },
    {
      "observed": true,
      "severity": "medio",
      "what": "A verificação condicional na mesma linha de cabeçalho da função ignora a variável higienizada e consulta a variável bruta para um caractere chave, reintroduzindo o mesmo vetor do erro corrigido no laço."
    },
    {
      "observed": false,
      "severity": "alto",
      "what": "Forte indicativo de que blocos que usem strings multilinhas continuarão reportando funções longas, já que o método de busca da regex linha-a-linha demanda aberturas e fechamentos estritamente não divididos por quebras de arquivo."
    }
  ],
  "limits": [
    "Não é possível atestar se as limitações com template literals ou com strings multilinhas causaram erros práticos neste GREEN porque o oráculo fornecido não possui testes que exercitem funções JavaScript e delimitadores não pareados.",
    "A ausência de falha no G0 sugere que a deficiência lógica, apesar de quebrar o gate, não tropeçou nos falsos positivos da árvore atual, operando invisivelmente sobre arquivos já sadios."
  ]
}
```

---

## 2. Contra-auditoria da missao reescrita, antes de delegar

Material: missao reescrita, oraculo integral, implementacao atual de
`_function_end`, limites 15 a 18, e o estado medido da arvore
(`sha256 4E50195B3730568CAAA781D908683E22...`).

Veredito: **REFUTADO**, `exit 1`. Nao delegar.

```json
{
  "backend": "agy",
  "auditor": "gemini-3.1-pro-high",
  "verdict": "REFUTADO",
  "questions": [
    "Existe algum teste no oráculo garantindo que funções longas em `.ts`, `.js` ou `.mjs` ainda disparam a regra `funcao-longa` após a mudança? Não. O único teste que cobre TypeScript (`test_template_literal_nao_expoe_a_chave`) exige apenas que uma função curta não seja reportada. Uma implementação que pare de contar chaves e cegue o gate para essas linguagens passará recebendo GREEN.",
    "O caminho de fallback exigido pela missão (cair na contagem de chaves atual quando o interpretador PowerShell não existe) é exercitado pela suíte? Não. O ambiente garante o PowerShell 7 no PATH e nenhum teste simula sua ausência ou injeta falha no subprocesso, logo uma implementação que lance exceção fatal em vez de fazer o fallback será aprovada."
  ],
  "findings": [
    {
      "observed": true,
      "severity": "alto",
      "what": "Cobertura ausente: Não há testes de verdadeiro positivo (função longa detectada) para JavaScript e TypeScript. O oráculo aceitará implementações plausíveis que quebrem a contagem do gate para essas linguagens, desde que funções curtas não gerem falsos positivos."
    },
    {
      "observed": true,
      "severity": "alto",
      "what": "Caminho de erro não exercitado: O fallback de segurança sem o PowerShell não possui cobertura no oráculo, permitindo que a missão seja validada mesmo se o operador ignorar essa cláusula de contorno."
    },
    {
      "observed": false,
      "severity": "medio",
      "what": "Hipótese de efeito colateral de desempenho: A função _function_end opera por função e não por arquivo. O operador pode invocar um processo pwsh separado a cada função (0,33s cada), o que degradaria severamente o tempo do pipeline real, mas passaria despercebido nos testes unitários focados em fixtures pequenas."
    }
  ],
  "limits": [
    "Não é possível afirmar como o operador transmitirá os dados para o PowerShell (stdin, parâmetro `-c` longo ou arquivo em disco referenciado), impedindo validação antecipada sobre falhas em caminhos relativos ou estouros de limite de tamanho na linha de comando."
  ]
}
```

### O que o gerente fez com cada achado

Os tres foram confirmados por medicao propria antes de virar teste. Nenhum foi
aceito por relato.

| achado | verificacao do gerente | destino |
|---|---|---|
| sem teste de verdadeiro positivo em JS/TS | dos quatro asserts que exigiam deteccao, tres eram `.ps1` e um `.py`; nenhum `.ts` | `test_funcao_longa_em_ts_e_medida_no_fim_exato` |
| caminho de degradacao nao exercitado | nenhuma referencia a ausencia de interpretador no oraculo | `test_sem_o_analisador_o_gate_degrada_e_nao_quebra` |
| custo por funcao em vez de por arquivo (hipotese) | nao medido; aceito como requisito por ser previsivel e barato | STOP CONDITION na missao |

---

## 3. Contra-leitura por painel, e o que ela achou

Um painel de quatro revisores da MESMA familia de modelo do gerente leu a missao
em sandbox somente-leitura, com um cetico tentando derrubar cada achado.

Isto e **contra-leitura, nao auditoria independente**: mesmo modelo do gerente,
viés compartilhado passa pelos dois. Registrado por completude, com peso menor
que as secoes 1 e 2.

Dois achados sobreviveram a refutacao, e os dois foram confirmados por medicao
do gerente:

- **`gates.py` a duas linhas do teto.** 598 linhas contra `max_file_lines = 600`,
  aplicado pelo `check_tree` sobre a arvore inteira. O `G0-fronteira` roda em
  toda iteracao, nao no push. Evidencia gravada em
  `runs/check-bloat-chave-em-string/20260831T174218.231Z/iter1`: `g5-testes`
  exit 0 PASS e `g0-fronteira` exit 1 FAIL, com
  `gates.py:642 [arquivo-longo] 642 linhas (teto 600)`. O operario tinha o
  oraculo verde e perdeu a iteracao so pelo teto.
  Destino: WRITE_SET passou a nomear um modulo novo, `blocks.py`.
- **O mutante `min(parser, contagem_crua)`.** Nenhuma fixture fazia a contagem
  crua fechar CEDO — ela ou estourava ate o EOF ou acertava. Medido:
  num `.ps1` cuja chave de fechamento em string precede qualquer abertura, a
  crua devolve 2 para uma funcao de 63 linhas.
  Destino: `test_chave_de_fechamento_em_string_nao_encerra_a_funcao_cedo`.

---

## Limites deste registro

- **As tres execucoes usaram o mesmo backend e o mesmo modelo.** Nao ha
  diversidade de fornecedor aqui. A reserva NVIDIA nao foi exercitada.
- **O auditor nao executou nada.** Le e raciocina sobre mutantes. Nenhum achado
  dele foi verificado por execucao — a verificacao foi do gerente, depois.
- **A captura perdeu o encoding.** Os vereditos foram redirecionados pelo shell
  e gravados em cp850, nao em UTF-8. O conteudo aqui foi decodificado de volta;
  o motor, quando grava `counter-audit.log` por conta propria, usa UTF-8 e nao
  tem esse problema. Capturar a mao custou fidelidade.
- **O experimento A/B tem n = 1 por variante.** Duas execucoes nao medem
  variancia. A conclusao vale para este material e este modelo.
- **O material da secao 1 foi reconstruido**, nao preservado: o run original nao
  guarda o material enviado ao auditor, apenas a resposta. A reconstrucao seguiu
  a mesma montagem do motor, e o hash acima ancora o que foi de fato enviado
  nesta repeticao — nao prova identidade com o envio original.
