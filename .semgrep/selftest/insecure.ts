// FIXTURE do autoteste do gate G4 — código inseguro PROPOSITAL.
// Não é importado por nada e não entra em build. Existe só para provar que o
// G4 REPROVA. Se parar de ser detectado, o ruleset quebrou e o autoteste
// falha — um gate que não reprova nada é pior que gate nenhum, porque mente.
//
// Sem fixture de segredo hardcoded de propósito: as regras de secrets ignoram
// valores de exemplo da documentação, e escrever algo que passe por credencial
// real só para acionar a regra é pior do que a cobertura vale.
//
// As duas regras abaixo são taint mode e casam FORMAS ESPECÍFICAS: o import
// tem de ser namespace de 'child_process' (sem o prefixo 'node:') e a fonte
// tem de ser parâmetro de função. Trocar por `import { exec } from
// "node:child_process"` faz a regra deixar de disparar — não porque o código
// ficou seguro, mas porque a regra não reconhece a forma. Se editar este
// fixture, rode o autoteste e confira a contagem de findings.

import * as cp from "child_process";

declare const window: { location: { href: string } };

// esperado: javascript.lang.security.detect-eval-with-expression (WARNING)
export function evalFromUrl(): unknown {
  return eval(window.location.href);
}

// esperado: javascript.lang.security.detect-child-process (ERROR)
export function shellFromInput(userInput: string): void {
  cp.exec(`ls ${userInput}`);
}
