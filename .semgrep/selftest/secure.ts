// FIXTURE do autoteste do gate G4 — código SEGURO equivalente.
// Prova o outro lado: o ruleset não é ruidoso a ponto de reprovar código são.
// Sem isto, um gate que reprovasse TUDO passaria no autoteste.

import { execFile } from "node:child_process";

export function listDir(dir: string): void {
  execFile("ls", [dir], () => {});
}

export function parseNumber(input: string): number {
  const n = Number(input);
  if (!Number.isFinite(n)) throw new RangeError(`not a number: ${input}`);
  return n;
}
