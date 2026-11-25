"""Conexão com o SQL Server a partir do .env (nunca versionado)."""
from __future__ import annotations

import os
from pathlib import Path
from urllib.parse import quote_plus

ROOT = Path(__file__).resolve().parents[2]


def connection_string() -> str:
    try:
        from dotenv import load_dotenv

        load_dotenv(ROOT / ".env")
    except ImportError:  # pragma: no cover
        pass
    server = os.getenv("SQL_SERVER", "localhost")
    database = os.getenv("SQL_DATABASE", "ANS_BI")
    driver = os.getenv("SQL_DRIVER", "ODBC Driver 18 for SQL Server")
    parts = [f"DRIVER={{{driver}}}", f"SERVER={server}", f"DATABASE={database}"]
    if os.getenv("SQL_TRUSTED_CONNECTION", "yes").lower() in ("yes", "true", "1"):
        parts.append("Trusted_Connection=yes")
    else:
        parts += [f"UID={os.environ['SQL_USER']}", f"PWD={os.environ['SQL_PASSWORD']}"]
    # Driver 18 criptografa por padrão; em instância local com certificado autoassinado é preciso confiar nele.
    parts.append(f"TrustServerCertificate={os.getenv('SQL_TRUST_SERVER_CERTIFICATE', 'yes')}")
    return ";".join(parts)


def get_engine():
    from sqlalchemy import create_engine

    url = "mssql+pyodbc:///?odbc_connect=" + quote_plus(connection_string())
    return create_engine(url, fast_executemany=True, future=True)
