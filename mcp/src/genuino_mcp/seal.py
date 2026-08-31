"""Selo determinístico do conteúdo normativo do método.

O `method/` é conteúdo normativo copiado de uma origem selada. Uma alteração
acidental ali muda o que o método manda fazer, em silêncio, e nenhum teste de
código pegaria isso.

O selo é um manifesto de SHA-256 versionado junto com os arquivos. A CI regera
e compara: se divergir, o build falha. Isso transforma "alguém editou o
contrato sem dizer" de descoberta arqueológica em erro de build.

Uso:
    python -m genuino_mcp.seal write <dir> <manifesto>
    python -m genuino_mcp.seal check <dir> <manifesto>

Contrato de exit code:
    0  selo confere
    1  divergência medida
    2  não foi possível medir
"""

from __future__ import annotations

import hashlib
import sys
from pathlib import Path

# Ordenação por caminho POSIX: o manifesto precisa ser idêntico byte a byte
# quando gerado no Windows e no Linux, senão a CI acusa drift que não existe.
_ENCODING = "utf-8"


def compute(root: Path, exclude: Path | None = None) -> list[tuple[str, str]]:
    """Devolve (caminho relativo POSIX, sha256) de cada arquivo, ordenado.

    `exclude` tira o próprio manifesto da conta. Sem isso, um manifesto gravado
    dentro do diretório que ele sela se auto-reporta como não selado, e a
    verificação nunca passa — nem logo depois de ser gerada.
    """
    resolved_exclude = exclude.resolve() if exclude else None
    entries: list[tuple[str, str]] = []
    for path in sorted(root.rglob("*"), key=lambda p: p.as_posix()):
        if not path.is_file():
            continue
        if resolved_exclude and path.resolve() == resolved_exclude:
            continue
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        entries.append((path.relative_to(root).as_posix(), digest))
    return sorted(entries, key=lambda e: e[0])


def render(entries: list[tuple[str, str]]) -> str:
    return "".join(f"{digest}  {name}\n" for name, digest in entries)


def parse(text: str) -> list[tuple[str, str]]:
    entries: list[tuple[str, str]] = []
    for line in text.splitlines():
        if not line.strip():
            continue
        digest, _, name = line.partition("  ")
        entries.append((name.strip(), digest.strip()))
    return sorted(entries, key=lambda e: e[0])


def _write(root: Path, manifest: Path) -> int:
    entries = compute(root, exclude=manifest)
    if not entries:
        print(f"[INDETERMINADO] nenhum arquivo sob {root}")
        return 2
    manifest.write_text(render(entries), encoding=_ENCODING, newline="\n")
    print(f"[PASS] selo gravado: {len(entries)} arquivo(s) em {manifest}")
    return 0


def _check(root: Path, manifest: Path) -> int:
    if not manifest.exists():
        print(f"[INDETERMINADO] manifesto ausente: {manifest}")
        return 2

    current = compute(root, exclude=manifest)
    if not current:
        print(f"[INDETERMINADO] nenhum arquivo sob {root}")
        return 2

    expected = dict(parse(manifest.read_text(encoding=_ENCODING)))
    actual = dict(current)
    problems: list[str] = []

    for name, digest in actual.items():
        if name not in expected:
            problems.append(f"NAO SELADO: {name}")
        elif expected[name] != digest:
            problems.append(f"ALTERADO:   {name}")
    for name in expected:
        if name not in actual:
            problems.append(f"REMOVIDO:   {name}")

    if problems:
        print(f"[FAIL] o selo de {root} nao confere:")
        for problem in sorted(problems):
            print(f"    {problem}")
        print("\nSe a mudanca foi intencional, regere o selo e commite o manifesto.")
        return 1

    print(f"[PASS] selo confere: {len(actual)} arquivo(s).")
    return 0


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    if len(args) != 3 or args[0] not in {"write", "check"}:
        print(__doc__)
        return 2

    mode, root_arg, manifest_arg = args
    root = Path(root_arg).resolve()
    manifest = Path(manifest_arg).resolve()

    if not root.is_dir():
        print(f"[INDETERMINADO] nao e um diretorio: {root}")
        return 2

    return _write(root, manifest) if mode == "write" else _check(root, manifest)


if __name__ == "__main__":
    raise SystemExit(main())
