# Pré-voo de ambiente

Carregar esta referência apenas antes de executar ou recomendar ação técnica em ambiente
cujo estado ainda não foi observado nesta sessão. O pré-voo descobre o terreno; não audita
alegações — isso é papel do protocolo principal.

## Roteiro mínimo

1. Sistema operacional e shell reais (não presumidos), com versão quando relevante.
2. Diretório de trabalho efetivo.
3. Ferramentas necessárias presentes, com caminho ou versão observados.
4. Ferramentas necessárias ausentes — nomear o que falta antes de prometer o passo que
   dependeria delas.
5. Integrações disponíveis: CLI, MCP, SDK, API, credenciais e o estado de autenticação de
   cada uma.
6. Separar, entre os comandos planejados, os somente-leitura dos mutáveis; executar a
   descoberta apenas com os somente-leitura.
7. Recomendar o menor caminho verificável até o objetivo e o critério observável de pronto.

## Regras

- Não instalar, autenticar ou alterar nada durante o pré-voo sem autorização explícita.
- Presença de ferramenta não prova versão nem permissão: registrar o comando de verificação
  usado, não a suposição.
- Ambiente descoberto vale para esta sessão e esta máquina; não promover a outro host sem
  novo pré-voo.
- Se o pré-voo revelar que o pedido depende de recurso inexistente, reportar a lacuna como
  limite, em vez de simular o passo.
