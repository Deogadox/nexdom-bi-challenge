# Arquitetura técnica

`Python → STG → ODS → DW → Power BI`, com o **SQL Server como motor de tratamento e integração**.
O Python não aplica regra de negócio: coleta, carrega a STG como texto e orquestra a execução.

```
ANS FTP PDA
   │  [Python] src/extraction/download_ans.py   → data/raw/<fonte>/ + manifest.json (sha256, Last-Modified)
   │  [Python] src/exploration/profile_raw.py   → docs/profiling_raw.md   (somente inspeção)
   │  [Python] src/loading/load_stg.py          → STG.* (NVARCHAR, + metadados de controle)
   ▼
SQL Server  (banco ANS_BI)
   STG  ── dbo.usp_ODS_Organizacoes / usp_ODS_IGR / usp_ODS_TR / usp_ODS_Validacao ──►  ODS
   ODS  ── dbo.usp_DW_Dimensoes / usp_DW_Fatos / usp_DW_Validacao               ──►  DW
   dbo.usp_Pipeline_ANS orquestra tudo; CTL.LogExecucao e CTL.Rejeicao registram cada etapa
   ▲
   │  [Python] src/orchestration/run_pipeline.py: download → load_stg → EXEC usp_Pipeline_ANS
   │           → exporta resultados das checagens para logs/ (evidência de validação)
   ▼
[Python] src/analysis/*  (lê DW: Spearman/Pearson, IQR, z robusto, séries)  →  Power BI (Import do DW)
```

## Responsabilidades

| Camada | Tecnologia | Faz | Não faz |
|---|---|---|---|
| Coleta | Python (requests) | Download, hash, versionamento dos originais, logs | Alterar arquivos |
| STG / Bronze | Python (pandas só para ler + SQLAlchemy/pyodbc) → SQL | Cópia fiel, tudo texto, `IdExecucao`, `ArquivoOrigem`, `Sha256`, `DtCarga`, `NrLinhaArquivo` | Converter tipos ou corrigir valores |
| ODS / Silver | T-SQL (Stored Procedures) | Tipagem com `TRY_CONVERT`, registro ANS `CHAR(6)`, domínios, duplicidades, flags de qualidade, rejeições com motivo | Apagar registros silenciosamente |
| DW / Gold | T-SQL (Stored Procedures) | Estrela, chaves substitutas, cargas idempotentes (MERGE / delete-insert por competência) | Misturar grãos |
| Análises | Python (scipy) sobre o DW | Estatística, gráficos para relatório | Retratar dados |
| BI | Power BI | Medidas DAX, dashboard | Ler a STG |

Medallion é um paralelo **conceitual**: STG ≈ Bronze (preservado), ODS ≈ Silver (tratado e validado),
DW ≈ Gold (modelado para consumo). Não são sinônimos: o ODS aqui é tabular e operacional, não um lakehouse.

## Controle e auditoria (schema `CTL`)
- `CTL.Execucao` — uma linha por execução (`IdExecucao`, início/fim, status, origem).
- `CTL.LogEtapa` — etapa, linhas lidas/inseridas/rejeitadas, duração, mensagem de erro.
- `CTL.Rejeicao` — tabela, chave natural, linha do arquivo, regra violada, valor original.
- `CTL.ArquivoCarregado` — arquivo, sha256, competências contidas; evita recarga duplicada do mesmo arquivo.

Cada procedure usa `TRY/CATCH` + transação, grava o log e relança o erro para o orquestrador.

## Modelo dimensional (proposta — fechar após o profiling das bases completas)

| Tabela | Grão |
|---|---|
| `DW.DimOperadora` | registro ANS (ativas ∪ canceladas ∪ "sem cadastro" vindos dos fatos); status, UF, datas |
| `DW.DimSegmento` | modalidade do CADOP |
| `DW.DimTempo` | mês (2019-10 → última competência) |
| `DW.DimCobertura` / `DW.DimNatureza` | domínios do IGR / TR |
| `DW.FatoIGR` | operadora × cobertura × mês: reclamações, beneficiários, porte |
| `DW.FatoTR` | operadora × natureza × mês: numerador, denominador |

Fatos separados (quebras diferentes: cobertura vs natureza), sem relação entre si, ligados por `DimOperadora` e
`DimTempo`. Guardam numerador e denominador; o DAX recompõe as taxas com `DIVIDE(SUM, SUM)`.
O indicador combinado (pesos parametrizáveis) será calculado no DAX ou numa view `DW.vw_DesempenhoJanela`.

## Ambiente
- SQL Server: instância local do autor (Windows). Não há SQL Server no ambiente de desenvolvimento assistido
  (sem acesso ao registro de imagens da Microsoft); os scripts são executados localmente e as evidências
  de validação vêm de `logs/`.
- Agendamento: SQL Server Agent só será documentado como implementado se for configurado de fato.
