# Limites declarados

O que este método **não** garante. Cada item aqui foi encontrado por auditoria
independente, e nenhum tem correção puramente técnica — por isso está declarado
em vez de corrigido.

Um método que lista só o que faz bem não é um método, é propaganda.

---

## 1. A separação autor/juiz é real para o operário, não para o gerente

O método promete que "quem escreve o código nunca é quem atesta que ele
funciona". Isso vale para o operário: ele escreve num worktree, e os gates rodam
noutro, com o oráculo protegido.

**Não vale para o gerente.** Quem escreve o oráculo é o gerente. Se o teste de
aceitação for insuficiente, tautológico ou tendencioso, o motor o executa numa
árvore limpa, obtém exit 0 e grava `GREEN` — com toda a aparência de rigor.

A autoridade de medição é independente do *operário*, e inteiramente dependente
do *gerente*.

Não há como fechar isso com código: alguém precisa escrever o oráculo. O que
existe é revisão independente do oráculo por outro modelo, que é uma mitigação,
não uma garantia.

## 2. O `WRITE_SET` controla o transporte, não a execução

A allowlist decide o que entra no patch medido. Ela **não** sandbox o código
permitido — que roda no worktree de medição com os privilégios do motor.

Cenário reproduzido em auditoria:

```
WRITE_SET: src/pkg/__init__.py       TEST_CMD: pytest tests/
```

O `__init__.py` está legitimamente na allowlist. Se ele chamar `os._exit(0)`
durante a coleta, o processo termina com zero sem executar um único teste do
oráculo, e o motor aceita `GREEN`.

O equivalente em configuração: `WRITE_SET: package.json` com `TEST_CMD: npm
test` permite trocar o próprio script `test`.

**Mitigação parcial, não solução:** declare o `WRITE_SET` o mais estreito
possível, e prefira arquivos que o `TEST_CMD` não carrega automaticamente.
Um `WRITE_SET: src/` combinado com `TEST_CMD: pytest src/` reabre o furo do
`conftest.py` pela porta da frente.

## 3. Exit code não captura classes inteiras de defeito

Todo o veredito repousa em exit code. Passam com zero:

- asserção vazia — `try { ... } catch { }`, ou laço sobre coleção vazia
- vazamento de recurso, processo órfão, handle não fechado (o SO limpa na saída)
- condição de corrida que só falha sob carga ou latência real
- complexidade O(n²) que passa em milissegundos com cinco itens de teste
- caminho de código que o `TEST_CMD` simplesmente não exercita

Exit code é condição necessária. Não é suficiente, e o método não finge que é.

## 4. O baseline RED impede refatoração pura

O motor aborta se o teste de aceitação já passa no commit-base. Isso existe para
impedir GREEN vazio — mas cobra um preço real.

Numa refatoração que não muda comportamento, os testes **já passam**. O motor
recusa iniciar, e a única saída seria inventar um teste artificial só para
produzir RED sintético — que é pior que não usar o método.

**Quando não usar este loop:** refatoração pura, spike exploratório onde a causa
raiz ainda é desconhecida, e correção de uma linha. Nesses casos o overhead de
dois worktrees, baseline e patch filtrado custa mais do que entrega.

## 5. O `CODEX_HOME` do usuário define a capacidade real do operário

O sandbox `workspace-write` governa comandos de shell gerados pelo modelo. Ele
**não** governa chamadas de ferramenta MCP vindas de plugins do Codex.

Uma auditoria leu o `config.toml` da máquina de desenvolvimento e encontrou 15
plugins habilitados — entre eles Slack e Google Calendar — e um `notify`
apontando para um executável arbitrário disparado a cada turno.

Portanto: "o operário não acessa a rede" é hoje **promessa de prompt**, não
garantia do sandbox. O `verdict.json` registra o hash do motor e da missão, mas
nada sobre a configuração que determinou o que o operário podia fazer.

## 6. A evidência ancora os inputs, não o produto

O `verdict.json` grava `engine_sha256` e `mission_sha256` — o motor e a missão
que foram *lidos*. Não grava hash do `diff.patch`, que é o *resultado*.

Se alguém trocar o patch dentro de `runs/` depois que o veredito fecha, o
`verdict.json` continua matematicamente íntegro. A evidência é robusta quanto à
origem dos parâmetros e aberta quanto ao produto entregue.

Hashes conferem aparência forense a um documento. Vale ler quais elos eles
realmente fecham.

## 7. Cobertura de análise por linguagem é desigual

O `scan_security` usa regras vendorizadas do semgrep que cobrem Python de forma
estrutural. **Nenhum ruleset cobre PowerShell estruturalmente** — e o motor é
escrito em PowerShell.

Para os arquivos `.ps1` deste repositório, a análise é apenas detecção de
segredo por regex. É lacuna real, não escolha.

## 8. O corpo do loop não tem cobertura de teste

Os testes end-to-end do orquestrador rodam com `-DryRun`, que retorna antes do
laço de iteração. Não são exercitados por teste: a chamada ao operário, a
detecção de violação, a filtragem e aplicação do patch, a execução dos gates e
a decisão GREEN/RED.

Mutantes que sobreviveriam à suíte verde incluem mover o incremento de iteração
para antes do guard de não-medição — que reinstalaria exatamente o defeito que o
contrato de três faixas existe para impedir.

## 9. O `TEST_CMD` pode ler fora do repositório, e nada congela isso

`Invoke-Gate` fixa o diretório corrente do processo. Ele **não** confina o que o
comando lê.

Um `TEST_CMD` que abra caminho absoluto, suba com `..`, consulte serviço de rede
ou leia estado mutável do host escapa inteiramente do `WRITE_SET` e do `ORACULO`
— os dois governam o que viaja no patch, não o que o processo alcança.

Auditoria independente confirmou a ausência de controle. A exploração depende
das permissões do host, e o método não oferece nenhuma barreira aqui.

## 10. Symlink e submódulo não foram auditados neste host

Duas hipóteses ficaram **abertas e não reproduzidas**, ambas por limitação do
ambiente de desenvolvimento — não por terem sido descartadas:

- **Symlink.** O motor não rejeita entradas de modo `120000` nem canonicaliza o
  alvo. Num host com symlinks reais, um link dentro do `WRITE_SET` pode apontar
  para conteúdo fora dele. Neste checkout `core.symlinks=false`, e o cenário não
  pôde ser montado.
- **Submódulo.** O detector trata um gitlink como um caminho único, e
  `git apply` sem `--index` não materializa necessariamente o commit registrado.
  Não existe prova de equivalência entre o conteúdo medido e o gitlink
  arquivado. A árvore auditada não tinha submódulo.

Não reproduzido não é o mesmo que não existe. Estão aqui por isso.

## 11. A validação de pathspec confia na configuração do git do host

`Test-PositiveLiteralPathspec` rejeita a sintaxe mágica (`:`, `:!`, `:(attr:…)`,
`:/`), curinga e `..`. Isso fecha as três formas que a auditoria reproduziu para
declarar um `WRITE_SET` que não restringe nada.

O que ele não cobre: `core.quotePath`, `core.ignorecase` e `core.symlinks` são
do host e mudam como o git reporta e casa caminhos. As duas listas comparadas em
`Get-PathOutsideWriteSet` vêm do mesmo git com a mesma configuração, o que
mantém a comparação coerente — mas a coerência é com aquela configuração, não
com uma semântica absoluta.

## 12. `ls-tree` e `diff` não têm semântica de pathspec equivalente

A validação do oráculo usa `ls-tree`; a geração do patch usa `diff`. Auditoria
reproduziu que `ls-tree` rejeita `:(glob)`, `:(icase)`, `:(attr)` e `:(exclude)`
com exit 128, enquanto `diff` os aceita.

A divergência é **fail-closed**: o motor converte os dois casos em falso e aborta
com exit 2. Não produz GREEN falso. Produz um diagnóstico errado — um pathspec
válido pode ser reportado como erro de digitação.

Desde que `Test-PositiveLiteralPathspec` passou a rejeitar magia antes desse
ponto, o caso deixou de ser alcançável pela porta da frente. Fica registrado
porque a divergência entre os dois comandos continua existindo no código.

## 13. A evidência não viaja com o repositório

`runs/` está no `.gitignore`. Toda a evidência que a R2 exige — comando, saída,
exit code, `verdict.json`, `diff.patch` — existe apenas na máquina que rodou o
loop.

Consequência direta: **quem clona este repositório não pode verificar nenhum
veredito.** Os commits dizem que os gates passaram; o leitor tem a palavra do
autor, que é exatamente o que o método recusa aceitar em qualquer outro ponto.

O motivo do `.gitignore` é real — um run carrega caminhos absolutos do host,
nomes de worktree em `%TEMP%` e patches inteiros — mas o motivo explica a
exclusão, não a resolve.

O que fecharia: versionar um `verdict.json` sanitizado por missão, com os
hashes, os exit codes e os caminhos reduzidos a marcadores, deixando fora
apenas o patch e o transitório. Não está feito.

---

## Corrigidos, com a evidência

Um limite sai desta lista quando deixa de existir. Estes saíram:

| Era | Fechado por | Prova |
|---|---|---|
| `WRITE_SET: :`, `:!tests/` e `:(attr:x)` passavam pela contagem `Count > 0` e não restringiam nada | `Test-PositiveLiteralPathspec`, aplicada a write-set **e** oráculo em `Invoke-GreenLoop.ps1` | `engine/tests/GenuinoEngine.Tests.ps1`, bloco `Test-PositiveLiteralPathspec` |
| Rename de fora para dentro do write-set não era registrado: `git diff --name-only` reporta só a pós-imagem, e a subtração concluía que nada fora foi tocado | `--no-renames` em `Get-PathOutsideWriteSet` | `InvokeGreenLoop.Tests.ps1`, "nomeia o lado de FORA de um rename". O mutante `--find-renames` reprova o caso. |
| `-notcontains` é case-insensitive: num filesystem que distingue caixa, um `src/foo` permitido apagava um `SRC/FOO` externo da lista de violações | `-cnotcontains` | Caso condicional em `InvokeGreenLoop.Tests.ps1`, pulado no NTFS e executado na matriz ubuntu da CI |
| `.Trim()` colapsava `foo`, `" foo"` e `"foo "` num nome só | `Split-GitPathLine`, que remove apenas o `
` do CRLF | `InvokeGreenLoop.Tests.ps1`, bloco `Split-GitPathLine` |
| `check_bloat` reportava "nenhum sintoma em 18 arquivos" sem dizer quais: lia-se como "o repositório", enquanto um markdown de 606 KB passava ao lado | O sumário nomeia as extensões medidas e declara o que ficou fora | `mcp/src/genuino_mcp/gates.py`, retorno de `check_bloat` |

---

## Como este documento é mantido

Um limite sai daqui quando deixa de existir, com a evidência da correção. Não
sai por ter sido esquecido, nem por incomodar.

Se você encontrar um limite que não está aqui, ele pertence aqui.
