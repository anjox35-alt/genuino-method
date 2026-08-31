"""Testes do selo de integridade do conteudo normativo."""

from __future__ import annotations

from pathlib import Path

from genuino_mcp import seal


def _tree(root: Path) -> Path:
    (root / "skill").mkdir(parents=True)
    (root / "skill" / "SKILL.md").write_text("conteudo normativo\n", encoding="utf-8")
    (root / "contrato.json").write_text('{"regra": 1}\n', encoding="utf-8")
    return root


def test_write_e_check_conferem_logo_apos_gerar(tmp_path: Path) -> None:
    """Regressao: o manifesto morava dentro do diretorio selado e se
    auto-reportava como nao selado. A verificacao falhava mesmo recem-gerada."""
    root = _tree(tmp_path / "method")
    manifest = root / "MANIFEST.sha256"
    assert seal.main(["write", str(root), str(manifest)]) == 0
    assert seal.main(["check", str(root), str(manifest)]) == 0


def test_check_reprova_arquivo_alterado(tmp_path: Path) -> None:
    root = _tree(tmp_path / "method")
    manifest = root / "MANIFEST.sha256"
    seal.main(["write", str(root), str(manifest)])
    (root / "skill" / "SKILL.md").write_text("conteudo ADULTERADO\n", encoding="utf-8")
    assert seal.main(["check", str(root), str(manifest)]) == 1


def test_check_reprova_arquivo_novo_nao_selado(tmp_path: Path) -> None:
    root = _tree(tmp_path / "method")
    manifest = root / "MANIFEST.sha256"
    seal.main(["write", str(root), str(manifest)])
    (root / "intruso.md").write_text("entrou sem selo\n", encoding="utf-8")
    assert seal.main(["check", str(root), str(manifest)]) == 1


def test_check_reprova_arquivo_removido(tmp_path: Path) -> None:
    root = _tree(tmp_path / "method")
    manifest = root / "MANIFEST.sha256"
    seal.main(["write", str(root), str(manifest)])
    (root / "contrato.json").unlink()
    assert seal.main(["check", str(root), str(manifest)]) == 1


def test_check_indeterminado_sem_manifesto(tmp_path: Path) -> None:
    """Manifesto ausente nao e aprovacao nem reprovacao: e falta de medicao."""
    root = _tree(tmp_path / "method")
    assert seal.main(["check", str(root), str(root / "ausente.sha256")]) == 2


def test_check_indeterminado_se_alvo_nao_e_diretorio(tmp_path: Path) -> None:
    alvo = tmp_path / "arquivo.txt"
    alvo.write_text("x", encoding="utf-8")
    assert seal.main(["check", str(alvo), str(tmp_path / "m.sha256")]) == 2


def test_manifesto_e_estavel_entre_execucoes(tmp_path: Path) -> None:
    """Ordem instavel faria a CI acusar drift que nao existe."""
    root = _tree(tmp_path / "method")
    primeiro = seal.render(seal.compute(root))
    segundo = seal.render(seal.compute(root))
    assert primeiro == segundo
    # Caminhos em POSIX, para que Windows e Linux gerem o mesmo manifesto.
    assert "\\" not in primeiro


def test_argumentos_invalidos_devolvem_dois() -> None:
    assert seal.main([]) == 2
    assert seal.main(["modo-inexistente", "a", "b"]) == 2
