# Dados

Os dados **não são versionados** (veja `.gitignore`): são públicos, recriados pelos scripts e o manifesto registra a
versão exata de cada arquivo usado. A única exceção são as tabelas agregadas de resultados em `processed/analises/`.

```
data/
├── raw/                                  # gerado por: python -m src.extraction.download_ans
│   ├── manifest.json                     # URL, bytes, SHA-256, Last-Modified e data do download de cada arquivo
│   ├── operadoras_ativas/                # Relatorio_cadop.csv + dicionário .ods
│   ├── operadoras_canceladas/            # Relatorio_cadop_canceladas.csv + dicionário .ods
│   ├── igr/                              # pda-023-igr.csv + dicionário .ods + nota técnica .pdf
│   ├── tr/                               # pda-048-taxa_de_resolutividade.csv + dicionário .ods + nota técnica .pdf
│   └── <fonte>/_history/                 # versões anteriores, quando o arquivo remoto muda
└── processed/
    ├── profiling/profile.json            # gerado por: python -m src.exploration.profile_raw
    ├── dw/*.parquet + _manifest.json     # gerado por: python -m src.analysis.export_dw
    └── analises/*.csv + resultados.json  # gerado por: python -m src.analysis.analises (VERSIONADO)
```

- **Formato da ANS:** CSV com separador `;`, textos entre aspas, decimal com vírgula, UTF-8 (sem BOM; o leitor também aceita CP1252). Os scripts leem
  tudo como texto, para preservar os zeros à esquerda do registro ANS.
- **Arquivos originais nunca são alterados.** Uma nova versão só substitui a anterior depois que esta é movida para
  `_history/`.
- **Versão usada** (download de 25/11/2026): IGR e TR publicados em 10/11/2026; cadastros em 25/11/2026.
  Volume: IGR 17 MB (130.155 linhas), TR 6,6 MB (63.366), CADOP 0,3 MB (1.101) + 1,0 MB (3.085).
