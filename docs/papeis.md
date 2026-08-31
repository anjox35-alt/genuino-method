# Papéis: quem escreve, quem mede, quem audita

O método começou com dois papéis: **gerente** e **operário**. Isso resolve o
problema mais óbvio — quem escreve o código não é quem atesta que ele funciona.

Mas dois papéis deixam um buraco, e ele é fácil de não enxergar de dentro.

## O buraco

O gerente escreve o motor que mede o operário. Depois roda os próprios testes
sobre o próprio motor e declara que funciona.

Nesse momento o gerente é juiz em causa própria. É exatamente a falha que o
método condena no operário, só que uma camada acima — e portanto menos visível.

A prova de que o buraco é real: o motor gravava `diff.patch` usando
`git diff HEAD`, que não mostra arquivo untracked. Toda missão que criasse um
arquivo novo — a maioria — arquivava um patch vazio ao lado de um veredito
`GREEN`. **Vinte e sete testes automatizados não pegaram isso.** O defeito só
apareceu quando alguém leu a evidência à mão e perguntou por que o arquivo
estava vazio.

Testes provam o que o autor pensou em testar. Eles não cobrem o que ele não
pensou — e é justamente aí que mora o defeito que importa.

## Os três papéis

| Papel | Quem | Sandbox | Escreve | Nunca faz |
|---|---|---|---|---|
| Gerente | Claude Code | árvore principal | testes de aceitação, kernel, merge | delegar o kernel; declarar sucesso sem exit code |
| Operário | Codex | worktree descartável, sem rede | implementação do produto | tocar o kernel; alterar teste de aceitação |
| Revisor | Codex | somente leitura | nada | escrever; aprovar o que não leu |

O revisor é o mesmo Codex, com **permissão diferente**. Não é redundância: é a
mesma pessoa em outro papel, e a separação está no sandbox, não na promessa.

## Por que o kernel não vai para o operário

Regra R1: `engine/**`, `CLAUDE.md`, `AGENTS.md` e `.github/workflows/**` nunca
são delegados.

Se o operário escrevesse o loop que o mede, ele estaria redigindo as próprias
regras de aprovação. Um erro conveniente ali — um gate que sempre passa, um exit
code mal classificado — se tornaria invisível, porque a peça que deveria
detectá-lo é a mesma que foi escrita com o erro.

O vigiado não redige o regulamento da vigilância.

## Por que revisar não viola essa regra

Revisar não é redigir. O revisor roda em sandbox somente-leitura: ele lê,
aponta e argumenta, mas não pode alterar uma linha do que audita.

A distinção que sustenta isso:

- **Escrever o kernel** dá ao operário poder sobre as próprias regras.
- **Revisar o kernel** dá a ele poder de apontar, e a decisão continua com o
  gerente e com o autor.

Um revisor que pudesse editar o que revisa seria só um segundo autor.

## O que o revisor recebe

Contexto suficiente para achar defeito, e nada que induza a resposta:

- O contrato que o código promete cumprir.
- As regras que ele promete fazer valer.
- **Um defeito já encontrado, como calibragem** — para orientar a família de
  problema a procurar.
- Perguntas concretas, não "revise isto".
- Instrução explícita para dizer "não encontrei" em vez de inventar achado.

Essa última linha importa. Um revisor que sente que precisa entregar algo produz
achado decorativo, e achado decorativo treina o time a ignorar revisão.

## O que este arranjo ainda não resolve

- O revisor e o operário são o mesmo modelo. Segunda leitura do mesmo sistema é
  **contra-leitura**, não confirmação independente. Um viés compartilhado entre
  os dois papéis passa pelos dois.
- Ninguém audita o revisor.
- O autor humano continua sendo o único ponto onde uma decisão de escopo pode
  ser tomada, e isso é deliberado.

Nenhuma dessas três é resolvida por mais uma camada de agente. Registrá-las é
mais honesto do que escondê-las atrás de um organograma.
