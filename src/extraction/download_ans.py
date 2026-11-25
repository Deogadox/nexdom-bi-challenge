"""
Camada 1 — Coleta das bases oficiais da ANS (Portal de Dados Abertos / FTP PDA).

Baixa os arquivos de dados, dicionários e notas técnicas para data/raw/<fonte>/,
sem alterar o conteúdo, e grava um manifesto (data/raw/manifest.json) com:
URL, tamanho, SHA-256, Last-Modified do servidor e data/hora do download.

Cada execução preserva a versão anterior: se o arquivo remoto mudou (hash
diferente), a versão antiga é movida para data/raw/<fonte>/_history/.

Uso:
    python -m src.extraction.download_ans            # baixa tudo
    python -m src.extraction.download_ans --only igr # uma fonte
"""
from __future__ import annotations

import argparse
import hashlib
import json
import logging
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path

import requests

BASE = "https://dadosabertos.ans.gov.br/FTP/PDA"

# Fontes oficiais. Os datasets do dados.gov.br apontam para estes mesmos arquivos do FTP PDA.
SOURCES: dict[str, list[dict]] = {
    "operadoras_ativas": [
        {"url": f"{BASE}/operadoras_de_plano_de_saude_ativas/Relatorio_cadop.csv", "kind": "data"},
        {"url": f"{BASE}/operadoras_de_plano_de_saude_ativas/dicionario_de_dados_das_operadoras_ativas.ods", "kind": "dictionary"},
    ],
    # Necessária para enriquecer operadoras que aparecem no histórico de IGR/TR mas já foram canceladas.
    "operadoras_canceladas": [
        {"url": f"{BASE}/operadoras_de_plano_de_saude_canceladas/Relatorio_cadop_canceladas.csv", "kind": "data"},
        {"url": f"{BASE}/operadoras_de_plano_de_saude_canceladas/Dicionario_de_dados_das_operadoras_canceladas.ods", "kind": "dictionary"},
    ],
    "igr": [
        {"url": f"{BASE}/IGR/IGR_versao_2023/pda-023-igr.csv", "kind": "data"},
        {"url": f"{BASE}/IGR/IGR_versao_2023/Dicionario_IGR_versao_2023.ods", "kind": "dictionary"},
        {"url": f"{BASE}/IGR/IGR_versao_2023/Ficha_Nota_Tecnica_-_IGR.pdf", "kind": "methodology"},
    ],
    "tr": [
        {"url": f"{BASE}/taxa_de_resolutividade/pda-048-taxa_de_resolutividade.csv", "kind": "data"},
        {"url": f"{BASE}/taxa_de_resolutividade/dicionario-pda-048-taxa_de_resolutividade.ods", "kind": "dictionary"},
        {"url": f"{BASE}/taxa_de_resolutividade/Ficha_Nota_Tecnica_-_TR.pdf", "kind": "methodology"},
    ],
}

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "data" / "raw"
MANIFEST = RAW / "manifest.json"
LOG_DIR = ROOT / "logs"

log = logging.getLogger("download_ans")


def setup_logging() -> None:
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    fmt = "%(asctime)s | %(levelname)s | %(name)s | %(message)s"
    logging.basicConfig(
        level=logging.INFO,
        format=fmt,
        handlers=[
            logging.StreamHandler(sys.stdout),
            logging.FileHandler(LOG_DIR / "extraction.log", encoding="utf-8"),
        ],
    )


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def load_manifest() -> dict:
    if MANIFEST.exists():
        return json.loads(MANIFEST.read_text(encoding="utf-8"))
    return {"files": {}}


def download(url: str, dest: Path, session: requests.Session, retries: int = 3) -> dict:
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(dest.suffix + ".part")
    last_err: Exception | None = None
    for attempt in range(1, retries + 1):
        try:
            with session.get(url, stream=True, timeout=120) as r:
                r.raise_for_status()
                with tmp.open("wb") as f:
                    for chunk in r.iter_content(1 << 20):
                        f.write(chunk)
                headers = {k: r.headers.get(k) for k in ("Last-Modified", "Content-Length", "ETag")}
            break
        except requests.RequestException as e:  # pragma: no cover - rede
            last_err = e
            log.warning("Falha %s/%s em %s: %s", attempt, retries, url, e)
    else:
        raise RuntimeError(f"Não foi possível baixar {url}") from last_err

    new_hash = sha256(tmp)
    if dest.exists() and sha256(dest) != new_hash:
        hist = dest.parent / "_history"
        hist.mkdir(exist_ok=True)
        stamp = datetime.fromtimestamp(dest.stat().st_mtime).strftime("%Y%m%d_%H%M%S")
        shutil.move(dest, hist / f"{dest.stem}_{stamp}{dest.suffix}")
        log.info("Versão anterior preservada em _history/: %s", dest.name)
    tmp.replace(dest)
    return {
        "url": url,
        "path": dest.relative_to(ROOT).as_posix(),
        "bytes": dest.stat().st_size,
        "sha256": new_hash,
        "server_last_modified": headers.get("Last-Modified"),
        "downloaded_at_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--only", choices=sorted(SOURCES), nargs="*", help="Fontes a baixar")
    args = parser.parse_args(argv)
    setup_logging()

    manifest = load_manifest()
    session = requests.Session()
    session.headers["User-Agent"] = "nexdom-bi-challenge/1.0 (pesquisa academica)"

    for source in args.only or SOURCES:
        for item in SOURCES[source]:
            name = item["url"].rsplit("/", 1)[-1]
            dest = RAW / source / name
            log.info("Baixando [%s] %s", source, name)
            meta = download(item["url"], dest, session)
            meta.update({"source": source, "kind": item["kind"]})
            manifest["files"][meta["path"]] = meta
            log.info("OK %s | %.1f KB | sha256=%s…", name, meta["bytes"] / 1024, meta["sha256"][:12])

    manifest["last_run_utc"] = datetime.now(timezone.utc).isoformat(timespec="seconds")
    MANIFEST.write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")
    log.info("Manifesto gravado em %s", MANIFEST.relative_to(ROOT))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
