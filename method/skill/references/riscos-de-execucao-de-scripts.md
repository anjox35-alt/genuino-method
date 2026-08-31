# Riscos de execução de scripts

Carregar esta referência apenas antes de executar, recomendar ou aprovar um script —
PowerShell, shell POSIX, batch ou equivalente — especialmente quando gerado por IA,
reaproveitado de sessão antiga ou recebido de terceiros. O gate de perda de estado do
protocolo principal continua valendo; aqui está a taxonomia de efeitos colaterais.

## Taxonomia de efeitos colaterais

Classificar o script pelo efeito mais grave que ele pode produzir, após análise comando a
comando:

| Tag | Efeito |
| --- | --- |
| `READONLY` | só lê; nenhuma escrita observável |
| `INVENTARIO` | lê e cataloga ambiente |
| `DIAGNOSTICO` | lê e testa sem alterar estado |
| `CRIA_ARQUIVO` | cria arquivos novos sem tocar existentes |
| `ALTERA_ARQUIVO` | modifica conteúdo existente |
| `ALTERA_SISTEMA` | muda configuração, serviço, registro ou permissão |
| `ALTERA_REDE` | muda estado de rede ou expõe porta |
| `EXECUTA_CODIGO` | invoca código externo ou dinâmico (`iex`, `eval`, download+execução) |
| `BAIXA_ARQUIVO` | traz bytes de fora do ambiente |
| `REMOVE_ARQUIVO` | apaga arquivos |
| `REMOVE_SISTEMA` | apaga componentes de sistema, serviços ou volumes |
| `RISCO_ALTO` | combinação das anteriores, alvo sensível ou efeito não determinável |

## Análise mínima antes de executar

- Objetivo provável do script e se ele corresponde ao pedido real.
- O que lê, cria, altera e remove — listado, não resumido.
- Pré-condições (ferramentas, permissões, caminhos) e como capturar a saída como evidência.
- Critério observável de sucesso e de falha, definido antes da execução.
- Como executar com o menor privilégio e o menor escopo que ainda cumpre o objetivo.

## Regras

- Não declarar script seguro sem a análise comando a comando; nome e comentários não são
  evidência do comportamento.
- Tag `EXECUTA_CODIGO`, `REMOVE_*` ou `RISCO_ALTO` exige o gate de perda de estado do
  protocolo principal antes de qualquer execução.
- Saída capturada do script é evidência do que ocorreu; previsão da análise é hipótese até
  a execução confirmar.
