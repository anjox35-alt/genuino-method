> Nota de saneamento: caminhos absolutos da maquina de desenvolvimento foram
> substituidos por marcadores (`<REPO>`, `<HOME>`, `<CODEX_HOME>`,
> `<GEMINI_HOME>`, `<CLAUDE_HOME>`) antes do primeiro commit. Este repositorio
> e publico e caminho pessoal nao pertence a ele. Nenhuma outra palavra do
> relatorio foi alterada: conclusoes, numeros e vereditos sao os originais.

# Auditoria de Premissas — Relatório do Auditor

**Função:** Auditoria Epistêmica e de Premissas  
**Escopo:** Premissas de design, blindagem metodológica, superfícies não auditadas e integridade da evidência.  
**Metodologia:** Separação estrita entre **FATO CONFIRMADO** (inspeção direta de código/linhas) e **INFERÊNCIA** (análise de limites lógicos e premissas).

---

### 1. PREMISSA CENTRAL: "Quem escreve o código nunca é quem atesta que ele funciona"

**Veredito:** **A premissa é FALSA em dois níveis estruturais.** A separação existe apenas para o trabalho de produto do operário (Codex), mas desmorona na definição do oráculo e no desenvolvimento do próprio motor.

#### O que foi CONFIRMADO no código:
1. **O Kernel é 100% auto-atestado pelo Gerente:**
   - Em [`docs/papeis.md:L39-40`](file:///<GEMINI_HOME>/antigravity-cli/docs/papeis.md#L39-L40), a regra R1 determina: `engine/**, CLAUDE.md, AGENTS.md e .github/workflows/** nunca são delegados.`
   - Em [`docs/papeis.md:L10-14`](file:///<GEMINI_HOME>/antigravity-cli/docs/papeis.md#L10-L14), o próprio documento admite que o Gerente (Claude) escreve o motor e roda os testes sobre si mesmo. A separação Gerente/Operário não se aplica ao desenvolvimento do próprio método.
2. **O Gerente é o autor unilateral do Oráculo:**
   - Em [`engine/GenuinoEngine.psm1:L97-108`](file:///<GEMINI_HOME>/antigravity-cli/engine/GenuinoEngine.psm1#L97-L108) e [`engine/Invoke-GreenLoop.ps1:L154-158`](file:///<GEMINI_HOME>/antigravity-cli/engine/Invoke-GreenLoop.ps1#L154-L158), o motor lê `TEST_CMD`, `GATE_DA_FRONTEIRA` e `ORACULO` do arquivo de missão escrito pelo Gerente.
   - Em [`missions/smoke-delegacao.md:L17-23`](file:///<GEMINI_HOME>/antigravity-cli/missions/smoke-delegacao.md#L17-L23), o teste de aceitação é uma string inlined (`$out = & pwsh ... if ($out -ne 'GENUINO_OK') { exit 1 }; exit 0`) gerada e mantida exclusivamente pelo Gerente.

#### INFERÊNCIA:
- O motor garante com sucesso o isolamento físico da **execução** (Codex não altera o oráculo no worktree de medição). Porém, **quem decide o que constitui sucesso é o Gerente**. Se o Gerente escrever um teste insuficiente, tendencioso ou tautológico, o motor executará esse teste num worktree limpo, obterá exit code 0 e registrará `GREEN`.
- **Onde o Gerente atesta o próprio trabalho:** Na concepção da especificação e dos testes de aceitação. A autoridade de medição é independente do *operário*, mas é totalmente dependente do *gerente*.

---

### 2. O QUE O EXIT CODE NÃO CAPTURA

**Veredito:** O exit code é uma condição necessária, mas grosseiramente insuficiente. Diversas classes de defeitos graves produzem `exit 0` e são atestadas como `GREEN` pelo motor.

#### O que foi CONFIRMADO no código:
1. **Ponto cego do `git diff` em arquivos não rastreados já ocorreu na prática:**
   - Em [`docs/papeis.md:L16-21`](file:///<GEMINI_HOME>/antigravity-cli/docs/papeis.md#L16-L21), está registrado que `git diff HEAD` retornava `exit 0` com saída vazia para arquivos novos, gerando patches vazios ao lado de vereditos `GREEN` aprovados por 27 testes automatizados.
2. **O motor só avalia a presença de erros reportados pelo comando invocado:**
   - Em [`engine/GenuinoEngine.psm1:L258-267`](file:///<GEMINI_HOME>/antigravity-cli/engine/GenuinoEngine.psm1#L258-L267), `Invoke-Gate` executa `pwsh -NoProfile -NonInteractive -Command $Command`. O gate é cego para qualquer coisa que não altere `$LASTEXITCODE` ou que não dispare exceção terminante no PowerShell.

#### Classes concretas de defeitos que passam com `exit 0`:
1. **Tautologias e Asserções Vazias no Oráculo:**
   - Testes com `try { ... } catch { }` que engolem exceções.
   - Testes de coleções onde asserções em loop (`foreach ($x in $list) { Assert }`) passam com sucesso se a lista estiver vazia.
   - Scripts que verificam apenas a existência de um arquivo (`Test-Path`), mas não validam integridade, encoding (UTF-8 com/sem BOM) ou semântica do conteúdo.
2. **Vazamento de Recursos e Efeitos Colaterais Tardios:**
   - Processos órfãos em background, memory leaks ou file descriptor handles não fechados. Como o processo do gate é finalizado ([`engine/GenuinoEngine.psm1:L585-595`](file:///<GEMINI_HOME>/antigravity-cli/engine/GenuinoEngine.psm1#L585-L595)), o SO limpa os handles no encerramento e o exit code é `0`, mascarando o defeito em produção.
3. **Condições de Corrida (Race Conditions) e Não-Determinismo Temporal:**
   - Concorrência que só falha sob alta carga ou latência de rede real. Em testes unitários rápidos e isolados no SSD, o timing coincide e retorna `exit 0`.
4. **Vulnerabilidades de Segurança Lógica e Performance:**
   - Algoritmos de complexidade $O(N^2)$ ou $O(2^N)$ que passam em milissegundos com inputs de teste de 5 itens, mas causam Denial of Service em produção.
   - Falhas de sanitização ou injeção em caminhos não exercitados pelos parâmetros fixos do `TEST_CMD`.

---

### 3. O CUSTO DA DISCIPLINA: Quando o método atrapalha em vez de ajudar

**Veredito:** O método se torna contraproducente em quatro cenários reais: **refatorações puras**, **descoberta exploratória**, **mudanças atômicas simples** e **operações de I/O em ambientes Windows**.

#### O que foi CONFIRMADO no código:
1. **O Baseline RED obrigatório proíbe refatorações:**
   - Em [`engine/Invoke-GreenLoop.ps1:L226-228`](file:///<GEMINI_HOME>/antigravity-cli/engine/Invoke-GreenLoop.ps1#L226-L228):
     ```powershell
     if ($baseline.ExitCode -eq 0) {
         Stop-Loop $EXIT_UNKNOWN 'ABORTADO: o teste de aceitacao JA PASSA no commit-base. RED nao confirmado; nao ha o que delegar.'
     }
     ```
2. **Allowlist estrita e imutável de caminhos (`WRITE_SET`):**
   - Em [`engine/Invoke-GreenLoop.ps1:L270-291`](file:///<GEMINI_HOME>/antigravity-cli/engine/Invoke-GreenLoop.ps1#L270-L291), qualquer escrita do operário fora do `WRITE_SET` pré-declarado causa `Stop-Loop $EXIT_RED` imediato, abortando a iteração.

#### Situações onde o método custa mais do que entrega:
1. **Refatoração de Código Existente (Sem alteração comportamental):**
   - Em uma refatoração pura (ex: quebrar um arquivo gigante em submódulos ou renomear rotinas internas sem mudar API), os testes de aceitação existentes **já passam** no commit base (`exit 0`).
   - O motor **recusa-se a iniciar** (L226). Para conseguir rodar o loop, o desenvolvedor é obrigado a inventar um teste artificial e frágil (ex: verificar regex do código-fonte ou contagem de linhas) apenas para produzir um `RED` sintético.
2. **Fase de Diagnóstico e Spikes Exploratórios:**
   - Quando a causa raiz de um bug é desconhecida, você não sabe de antemão qual teste escrever nem quais arquivos colocar no `WRITE_SET`. Exigir preencher os 6 campos normativos antes de explorar o problema paralisa a investigação.
3. **Descoberta de Dependências Imprevistas durante a Implementação:**
   - Se o operário descobrir que precisa ajustar uma constante em um arquivo utilitário fora do `WRITE_SET` para satisfazer o contrato, a iteração é reprovada sumariamente (L290). O loop queima uma iteração e exige que o Gerente refaça o manifesto da missão.
4. **Custo de Fricção e I/O no Windows:**
   - Para correções de 1 linha (ex: corrigir um erro de digitação em documentação ou alterar uma URL de configuração), a criação de 2 worktrees no disco temporário, execução de baseline, lançamento do processo isolado do Codex e aplicação de patch gera overhead massivo de tempo, I/O e tokens sem nenhum ganho real de segurança.

---

### 4. O QUE NINGUÉM AUDITOU: A Área de Maior Risco

**Veredito:** A área de maior risco não auditada é a **desconexão crítica entre os Workflows de CI (`.github/workflows/verify-mcp.yml`) e o Kernel do motor (`engine/**`)**.

#### O que foi CONFIRMADO no código:
1. **A CI não executa sobre alterações no Kernel (`engine/**`):**
   - Em [`.github/workflows/verify-mcp.yml:L6-13`](file:///<GEMINI_HOME>/antigravity-cli/.github/workflows/verify-mcp.yml#L6-L13):
     ```yaml
     paths:
       - "mcp/**"
       - ".github/workflows/verify-mcp.yml"
     ```
   - **Fato:** Se qualquer alteração for feita em [`engine/Invoke-GreenLoop.ps1`](file:///<GEMINI_HOME>/antigravity-cli/engine/Invoke-GreenLoop.ps1) ou [`engine/GenuinoEngine.psm1`](file:///<GEMINI_HOME>/antigravity-cli/engine/GenuinoEngine.psm1), **a CI do GitHub simplesmente NÃO roda**. O motor não tem esteira de integração contínua configurada para si mesmo.
2. **O gate de publicação (`check_tree.py`) não valida o selo normativo que afirma proteger:**
   - Em [`mcp/src/genuino_mcp/check_tree.py:L50-54`](file:///<GEMINI_HOME>/antigravity-cli/mcp/src/genuino_mcp/check_tree.py#L50-L54), a docstring afirma que `method/` responde ao gate de selo (`genuino_mcp.seal`).
   - Em [`mcp/src/genuino_mcp/check_tree.py:L66-73`](file:///<GEMINI_HOME>/antigravity-cli/mcp/src/genuino_mcp/check_tree.py#L66-L73), os resultados executados são **apenas**: `scan_secrets`, `check_bloat` e `selftest_security`. **O gate de selo (`seal`) não é chamado em lugar nenhum do CLI.**
3. **Assimetria de Plataforma nos Gates de Publicação:**
   - Em [`.github/workflows/verify-mcp.yml:L68`](file:///<GEMINI_HOME>/antigravity-cli/.github/workflows/verify-mcp.yml#L68), o `publish-gate` roda exclusivamente em `ubuntu-latest`.
   - No entanto, [`engine/GenuinoEngine.psm1:L490-514`](file:///<GEMINI_HOME>/antigravity-cli/engine/GenuinoEngine.psm1#L490-L514) contém lógica complexa específica de resolução de binários para Windows (`.cmd`, `.bat`, `.ps1`, `ProcessStartInfo`). O ambiente de publicação valida Linux, mas o código operacional depende de idiossincrasias do Windows.

#### INFERÊNCIA sobre o risco:
- O projeto possui uma falsa sensação de blindagem na CI. Acredita-se que o repositório é protegido por gates automáticos, mas as modificações no motor PowerShell (o coração de toda a governança) trafegam sem nenhuma validação automatizada em pull requests.

---

### 5. AUTOENGANO ESTRUTURAL NA FORMA DA EVIDÊNCIA

**Veredito:** O motor produz artefatos com **"aparência de prova criptográfica"**, mas que possuem **elos abertos de integridade**, permitindo a validação de estados inconsistentes.

#### O que foi CONFIRMADO no código:
1. **O hash SHA256 não ancora o artefato produzido (`diff.patch`):**
   - Em [`engine/Invoke-GreenLoop.ps1:L353-376`](file:///<GEMINI_HOME>/antigravity-cli/engine/Invoke-GreenLoop.ps1#L353-L376), o `verdict.json` calcula e armazena:
     - `engine_sha256 = (Get-FileHash $PSCommandPath).Hash` (hash do script do motor)
     - `mission_sha256 = (Get-FileHash $missionFile).Hash` (hash do arquivo de missão)
   - **Fato:** O `verdict.json` **NÃO calcula o hash do `diff.patch` gerado**, nem dos logs de teste (`g5-testes.log`), nem do commit final.
2. **Textos de limites e isenções são estáticos e hardcoded:**
   - Em [`engine/Invoke-GreenLoop.ps1:L371-375`](file:///<GEMINI_HOME>/antigravity-cli/engine/Invoke-GreenLoop.ps1#L371-L375), o campo `limits` grava sempre três frases fixas, independentemente do que ocorreu durante a execução da missão.
3. **Os metadados dos gates gravam status PASS baseado em exit code sem validação de conteúdo:**
   - Em [`engine/GenuinoEngine.psm1:L216-224`](file:///<GEMINI_HOME>/antigravity-cli/engine/GenuinoEngine.psm1#L216-L224), `Invoke-Gate` grava um JSON estruturado com timestamp UTC ISO 8601, nome do comando e `status = PASS` se `$Code -eq 0`.

#### INFERÊNCIA sobre a forma da evidência:
- **Aparência vs. Substância:** A presença de hashes SHA-256 no `verdict.json` confere uma autoridade quase forense ao documento. No entanto, esses hashes provam apenas *qual versão do motor e da missão foram lidas na inicialização*.
- Se após a gravação do veredito um agente ou script corromper ou trocar o arquivo `diff.patch` dentro da pasta de evidências `runs/$missionId/$runId/`, **o `verdict.json` continuará matematicamente íntegro**, porque o produto do trabalho (`diff.patch`) não foi incluído no selo criptográfico.
- A evidência é robusta quanto à *origem dos parâmetros*, mas vulnerável quanto ao *resultado entregue*.

---

### Resumo Epistêmico das Premissas

| Premissa do Método | Realidade no Código | Classificação |
|---|---|---|
| *Separabilidade entre autor e juiz* | Real para o operário (Codex); inexistente para o gerente (Claude) e para o oráculo. | **Parcialmente Ilusória** |
| *Exit code como árbitro absoluto* | Cego a asserções vazias, leaks, corridas e erros conceituais de teste. | **Insuficiente** |
| *Disciplina de baseline RED universal* | Impede refatorações legítimas e spikes de diagnóstico. | **Rígida / Obstrutiva** |
| *Proteção total por gates de CI* | CI ignora completamente o diretório `engine/` e não valida selos em `method/`. | **Falsa Sensação de Segurança** |
| *Evidência auto-contida inatacável* | Hashes protegem inputs do motor, mas deixam o patch final sem amarração. | **Assinatura Incompleta** |
