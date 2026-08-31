"""Build a public record from a local verdict."""

from __future__ import annotations

import hashlib
import json
import re
import tempfile
from pathlib import Path


class PublicacaoRecusada(Exception):
    """Raised when a verdict cannot be made public safely."""


_REQUIRED_FIELDS = (
    "mission_id",
    "run_id",
    "verdict",
    "iterations",
    "write_set",
    "oracle_paths",
    "engine_sha256",
    "mission_sha256",
)
_SEPARATOR = r"[\\/]+"
_DRIVE_PATH = re.compile(r"[A-Za-z]:[\\/]+")
_UNC_PATH = re.compile(r"\\{2,}[^\\/\s]+[\\/]+")
_FORWARD_UNC_PATH = re.compile(r"(?<![:/])/{2,}[^/\s]+/+")
_UNIX_PATH = re.compile(r"(?<!<REPO>)(?<!<HOME>)(?<!<TMP>)(?<![\w./\\])/(?![/\s])\S+")
_ABSOLUTE_PATHS = (_DRIVE_PATH, _UNC_PATH, _FORWARD_UNC_PATH, _UNIX_PATH)
_MARKER_SEPARATOR = re.compile(r"(<(?:REPO|TMP|HOME)>)[\\/]+")
_PARENT_SEGMENT = re.compile(r"(?<=[\\/])\.\.(?=$|[\\/])")


def _compile_prefix(path: Path, marker: str, name: str) -> tuple[int, re.Pattern[str], str]:
    text = str(path)
    flags = 0

    if re.match(r"^[A-Za-z]:[\\/]+", text):
        trimmed = text.rstrip("\\/")
        drive = trimmed[:2]
        parts = [part for part in re.split(r"[\\/]+", trimmed[2:]) if part]
        body = re.escape(drive) + _SEPARATOR + _SEPARATOR.join(map(re.escape, parts))
        boundary = r"(?=$|[\\/])"
        flags = re.IGNORECASE
    elif text.startswith("\\\\"):
        trimmed = text.rstrip("\\/")
        parts = [part for part in re.split(r"[\\/]+", trimmed) if part]
        body = r"\\{2,}" + _SEPARATOR.join(map(re.escape, parts))
        body = rf"(?<![:\w.<>/\\-]){body}"
        boundary = r"(?=$|[\\/])"
        flags = re.IGNORECASE
    elif text.startswith("/"):
        trimmed = text.rstrip("/")
        parts = [part for part in re.split(r"/+", trimmed) if part]
        root = r"/{2,}" if text.startswith("//") else r"/+"
        body = root + r"/+".join(map(re.escape, parts))
        body = rf"(?<![:\w.<>/\\-]){body}"
        boundary = r"(?=$|/)"
    else:
        raise PublicacaoRecusada(f"{name} não é caminho absoluto: {text!r}")

    if not parts:
        raise PublicacaoRecusada(f"{name} é amplo demais para sanitização: {text!r}")

    pattern = re.compile(body + boundary, flags)
    specificity = sum(len(part) for part in parts)
    return specificity, pattern, marker


def _prefixes(
    repo_root: Path,
    tmp_dir: Path,
    home_dir: Path,
) -> list[tuple[re.Pattern[str], str]]:
    candidates = (
        (repo_root, "<REPO>", "repo_root", 0),
        (tmp_dir, "<TMP>", "tmp_dir", 1),
        (home_dir, "<HOME>", "home_dir", 2),
    )
    compiled = [
        (*_compile_prefix(path, marker, name), priority)
        for path, marker, name, priority in candidates
    ]
    compiled.sort(key=lambda item: (-item[0], item[3]))
    return [(pattern, marker) for _, pattern, marker, _ in compiled]


def _sanitize_string(
    value: str,
    prefixes: list[tuple[re.Pattern[str], str]],
    location: str,
) -> str:
    sanitized = value
    for pattern, marker in prefixes:
        sanitized = pattern.sub(marker, sanitized)
    sanitized = _MARKER_SEPARATOR.sub(r"\1/", sanitized)

    parent = _PARENT_SEGMENT.search(sanitized)
    if _MARKER_SEPARATOR.search(sanitized) is not None and parent is not None:
        raise PublicacaoRecusada(
            f"caminho escapa prefixo sanitizado em {location}: {parent.group(0)!r}"
        )

    for pattern in _ABSOLUTE_PATHS:
        match = pattern.search(sanitized)
        if match is not None:
            raise PublicacaoRecusada(
                f"caminho absoluto remanescente em {location}: {match.group(0)!r}"
            )
    return sanitized


def _sanitize(
    value: object,
    prefixes: list[tuple[re.Pattern[str], str]],
    location: str = "$",
) -> object:
    if isinstance(value, str):
        return _sanitize_string(value, prefixes, location)
    if isinstance(value, list):
        return [
            _sanitize(item, prefixes, f"{location}[{index}]") for index, item in enumerate(value)
        ]
    if isinstance(value, dict):
        sanitized: dict[str, object] = {}
        for key, item in value.items():
            if not isinstance(key, str):
                raise PublicacaoRecusada(f"chave JSON inválida em {location}: {key!r}")
            clean_key = _sanitize_string(key, prefixes, f"{location}.<chave>")
            if clean_key in sanitized:
                raise PublicacaoRecusada(
                    f"colisão de chaves após sanitização em {location}: {clean_key!r}"
                )
            sanitized[clean_key] = _sanitize(item, prefixes, f"{location}.{clean_key}")
        return sanitized
    return value


def build_public_verdict(
    verdict_path: Path,
    *,
    repo_root: Path,
    tmp_dir: Path | None = None,
    home_dir: Path | None = None,
) -> dict:
    """Return a sanitized public record derived from ``verdict_path``."""
    path = Path(verdict_path)
    try:
        original = path.read_bytes()
    except OSError as exc:
        raise PublicacaoRecusada(f"não foi possível ler {path!s}: {exc}") from exc

    verdict_sha256 = hashlib.sha256(original).hexdigest()
    try:
        data = json.loads(original)
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        raise PublicacaoRecusada(f"verdict.json inválido: {exc}") from exc

    if not isinstance(data, dict):
        raise PublicacaoRecusada("verdict.json precisa conter um objeto JSON")

    missing = [field for field in _REQUIRED_FIELDS if field not in data]
    if missing:
        raise PublicacaoRecusada(f"campos obrigatórios ausentes: {', '.join(missing)}")

    effective_tmp = Path(tempfile.gettempdir()) if tmp_dir is None else Path(tmp_dir)
    effective_home = Path.home() if home_dir is None else Path(home_dir)
    sanitized = _sanitize(data, _prefixes(Path(repo_root), effective_tmp, effective_home))
    if not isinstance(sanitized, dict):
        raise PublicacaoRecusada("verdict.json precisa conter um objeto JSON")
    sanitized["verdict_sha256"] = verdict_sha256
    return sanitized
