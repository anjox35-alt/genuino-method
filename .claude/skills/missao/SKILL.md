---
name: missao
description: Cria o arquivo de missao do green loop com os seis campos obrigatorios preenchidos e o TEST_CMD ja medindo lint e formatacao. Use ao abrir qualquer missao nova para o operario.
---

# Nova missao do green loop

Escreve `missions/<id>.md` no formato que `Read-Mission` exige, e nada alem
disso. Nao delega, nao roda o loop, nao escreve codigo.

## Por que esta skill existe

O `TEST_CMD` define o que e medido. O que fica fora dele nao e medido, e o que
nao e medido nao pode ser cobrado de ninguem.

Isso ja custou duas missoes nesta base:

- `selo-no-gate-de-publicacao` levou so `pytest` no comando. O operario entregou
  GREEN correto e o `ruff check` reprovou depois, em arquivo do gerente.
- `nucleo-01-veredito-publicavel` levou `pytest` e `ruff check`, mas nao
  `ruff format --check` -- que e gate na CI. O arquivo do operario reprovou no
  push, e ele nao tinha como saber.

Duas vezes o mesmo defeito, um degrau acima a cada vez. Um template nao impede
o erro de julgamento, mas impede o de esquecimento.

## Campos obrigatorios

`Read-Mission` recusa a missao se faltar qualquer um destes:

| Campo | O que responde |
|---|---|
| `TEST_CMD` | Como se mede que o trabalho ficou pronto |
| `FRONTEIRA` | Qual uso real precisa funcionar |
| `GATE_DA_FRONTEIRA` | Como se mede aquele uso real |
| `PRE_REQUISITOS_HUMANOS` | O que o motor NAO verifica |
| `ORACULO` | O que o operario nao pode tocar |
| `WRITE_SET` | O unico lugar onde ele pode escrever |

## Procedimento

1. **Escreva o objetivo em uma frase.** Se nao couber numa frase, a missao esta
   grande demais: o motor tem teto de 5 iteracoes e uma missao gorda estoura
   antes de entregar.

2. **Declare o `WRITE_SET` o mais estreito possivel.** Ele e allowlist, e cada
   caminho a mais e superficie que o operario pode alterar sem ser notado.
   Precisa ser positivo e literal -- `Test-PositiveLiteralPathspec` recusa
   magia de pathspec (`:`, `:!`, `:(attr:...)`) e curinga.

3. **Monte o `TEST_CMD` com TODOS os gates que a CI roda.** Para este
   repositorio, em PowerShell, encadeando por exit code:

   ```
   TEST_CMD: $env:UV_LINK_MODE='copy'; Set-Location mcp; uv run pytest tests/<arquivo> -q; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; uv run ruff check .; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; uv run ruff format --check .; exit $LASTEXITCODE
   ```

   `UV_LINK_MODE=copy` nao e precaucao: sem ele o `uv` tenta hardlink do cache
   e o OneDrive recusa com `os error 396`.

4. **Escreva o `GATE_DA_FRONTEIRA` medindo coisa diferente do `TEST_CMD`.** Um
   teste pode passar com a funcionalidade chamada em silencio; a fronteira
   exige que ela apareca no uso real.

5. **Liste as STOP CONDITIONS.** No minimo: tocar o oraculo, escrever fora do
   write-set, e instalar dependencia.

6. **Confirme o RED antes de delegar.** Rode o `TEST_CMD` e registre o exit
   code. Precisa ser **1** -- reprovacao medida.

   Se der **2**, o loop aborta sem delegar: 2 significa "nao foi possivel
   medir". Num modulo que ainda nao existe, o `ImportError` no topo do arquivo
   de teste e erro de COLETA e produz 2. Adie o import para dentro de um helper
   e a falha vira N testes reprovados, que e o RED que o motor aceita.

7. **Mande o oraculo ao contra-auditor antes do operario ver qualquer coisa:**

   ```
   pwsh -File engine/Invoke-Auditor.ps1 < material.txt
   ```

   O auditor ja reprovou dois oraculos meus antes de virarem contrato. Um
   oraculo que ninguem contestou e uma regua que so o gerente conferiu.

## O que esta skill nao faz

Nao decide o que a missao deve fazer. Template preenchido com objetivo vago
produz missao vaga -- e o operario entrega exatamente o que foi pedido.
