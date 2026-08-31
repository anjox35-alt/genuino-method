# smoke-delegacao — prova que a delegação ao operário funciona de ponta a ponta

OBJETIVO: criar `engine/samples/Get-GenuinoGreeting.ps1`, um script PowerShell
que escreve exatamente `GENUINO_OK` na saída padrão e sai com código 0.

Missão deliberadamente trivial. Ela não existe para entregar funcionalidade:
existe para levar o loop inteiro até o fim com um operário real, e produzir a
evidência que hoje falta no relatório de auditoria — onde
`codex_delegation_e2e` está registrado como `null`.

Um objetivo trivial é a escolha certa aqui. Se o loop falhar, a causa vai ser o
loop, não a dificuldade da tarefa.

WRITE-SET:
- engine/samples/Get-GenuinoGreeting.ps1   (criar)

TEST_CMD: if (-not (Test-Path './engine/samples/Get-GenuinoGreeting.ps1')) { exit 1 }; $out = & pwsh -NoProfile -File './engine/samples/Get-GenuinoGreeting.ps1'; if ($out -ne 'GENUINO_OK') { exit 1 }; exit 0

FRONTEIRA: pwsh 7 nesta máquina, o mesmo interpretador onde os gates rodam
GATE_DA_FRONTEIRA: $out = & pwsh -NoProfile -File './engine/samples/Get-GenuinoGreeting.ps1'; if ($out -ne 'GENUINO_OK') { exit 1 }; exit 0
PRE_REQUISITOS_HUMANOS: NENHUM
ORACULO: NENHUM
WRITE_SET: engine/samples/

STOP CONDITIONS:
- Qualquer arquivo fora do write-set: reprovação imediata.
- Dependência nova: BLOCKED. Nenhuma é necessária.
- Alteração do TEST_CMD ou do gate de fronteira: violação do contrato do operário.

NOTA SOBRE O ORACULO: esta missao declara NENHUM porque o teste de aceitacao
vive dentro do proprio TEST_CMD, na missao, e nao num arquivo do repositorio. O
operario nao tem como alcancar a missao a partir do worktree. Numa missao real
com testes versionados, ORACULO listaria esses caminhos e eles seriam excluidos
do patch antes da medicao.

NOTA SOBRE A FRONTEIRA: o gate de fronteira aqui é quase igual ao TEST_CMD, e
isso é honesto para esta missão — a fronteira declarada *é* o interpretador
local. Numa missão real os dois divergem: os testes provam o que os testes
cobrem, e a fronteira prova que a coisa funciona onde precisa funcionar.
