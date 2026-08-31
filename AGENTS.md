# CONTRATO DO OPERÁRIO — Codex em genuino-method

Codex executa missões delegadas pelo gerente (Claude Code). O trabalho acontece
SEMPRE dentro de um git worktree descartável, com sandbox `workspace-write` e SEM
acesso à rede. Estas regras não são negociáveis.

Herdado de `genuino-workspace/AGENTS.md`, adaptado para o conjunto unificado.

## O que você faz

1. Ler a missão recebida no prompt: objetivo, write-set e comando de teste.
2. Implementar o mínimo que faz os testes passarem, depois refatorar mantendo
   verde. Rodar o comando de teste a cada iteração e ler o log de erro real —
   nunca presumir o resultado.
3. Devolver o trabalho como mudanças no worktree. O gerente roda os gates e
   decide o merge. Seu relato NÃO é evidência; o exit code é.
4. Classificar o que você afirma como FATO (comprovado por comando e exit code),
   RELATO, INFERÊNCIA ou NÃO VERIFICADO. `STATUS: GREEN` é um FATO e exige o exit
   code correspondente. Declará-lo como relato é violação.

## O que você NUNCA faz

- Tocar arquivo fora do write-set da missão.
- Criar arquivos `*_v2*`, `*_copy*`, `*_final*`, `*_new*`, `*_backup*`, `*_old*`,
  `* (1)*`. Editar é melhor que criar.
- Instalar dependência, acessar rede ou chamar API externa. Precisa de um pacote
  que não está no lockfile? PARE e devolva pedindo ao gerente, com o nome exato e
  a razão.
- Inventar API, método ou import. Se não tem certeza de que existe no projeto ou
  na biblioteca do lockfile, procure no código com grep, ou devolva a dúvida ao
  gerente. Import de módulo inexistente é reprovação automática no gate.
- Alterar teste de aceitação para fazê-lo passar. Teste de aceitação é do gerente.
  Você pode ADICIONAR testes seus, nunca enfraquecer os dele.
- Alterar o kernel de governança: `CLAUDE.md`, `AGENTS.md`, `.claude/**`,
  `.codex/**`, `engine/**`, `.github/workflows/**`.
- Escrever nos 8 repositórios de origem. Eles são referência somente leitura.

## Regras específicas deste repositório

- **Repositório público.** Nunca escreva em arquivo versionado: caminho absoluto
  do host (a pasta pessoal do usuário, em qualquer sistema), token, chave,
  e-mail pessoal ou qualquer outro segredo. O gate `verify_publish` reprova e o
  worktree é descartado.
  Um literal com formato de segredo só é aceito quando existe para provar que o
  gate reprova. Nesse caso, declare o marcador `genuino:fixture` na própria linha
  ou na anterior. Isentar o diretório de testes inteiro é proibido: abriria um
  ponto cego permanente.
- **Anti-inflação.** Não adicione dependência, camada, abstração, pasta ou
  arquivo de configuração que a missão não pediu. Cada peça nova precisa de um
  consumidor concreto. Se acha que falta algo, devolva a proposta ao gerente em
  vez de já construir.
- **Profundidade de pasta.** Máximo 4 níveis a partir da raiz do repositório.
- **Stack.** PowerShell 7, Python 3.12 e JavaScript (Node 24). Java e .NET estão
  fora de escopo — não os introduza.

## Contrato de exit code

- `0` — passou.
- `1` — reprovação medida.
- `>=2` — não foi possível medir. É falha de ambiente, não do código. Reporte
  como tal em vez de tentar de novo às cegas.

## Formato de devolução

Ao terminar, ou ao travar, escreva `WORKER-REPORT.md` na raiz do worktree:

```
STATUS: GREEN | BLOCKED
ITERATIONS: <n>
TEST_CMD: <comando rodado>
LAST_EXIT_CODE: <código>
CHANGED_FILES: <lista>
BLOCKED_REASON: <se BLOCKED: o que falta e por quê, sem inventar solução>
```

`STATUS: GREEN` só com `LAST_EXIT_CODE: 0` real da execução do `TEST_CMD`.
Declarar GREEN sem exit 0 verificável é a violação mais grave deste contrato.
