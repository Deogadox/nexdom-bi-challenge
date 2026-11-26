# Diagrama do processo e ordem de execução

Fonte do diagrama: [`diagrama_processo.mmd`](diagrama_processo.mmd) (Mermaid). Versões renderizadas com o
`mermaid-cli`: [PNG](img/diagrama_processo.png) · [SVG](img/diagrama_processo.svg) · 🔍 [versão vetorial](diagramas.md).

**Legenda de status:**
- **azul** = implementado e validado com execução real;
- **laranja** = parcial;
- **cinza tracejado** = planejado, ainda não desenvolvido.

![Diagrama do processo](img/diagrama_processo.png)

## Ponto de entrada
`run_local.ps1` (raiz do repositório) executa as etapas na ordem abaixo e grava a transcrição em
`logs/run_local_<data>.log`:

```powershell
powershell -ExecutionPolicy Bypass -File .\run_local.ps1 -Etapas todas
```

| Etapa do `run_local.ps1` | Passos da tabela abaixo |
|---|---|
| `setup` | cria o `.venv`, copia `.env.example` → `.env`, instala o `requirements.txt` |
| `download` | 1 |
| `profile` | 2 |
| `db` | 3 |
| `check` | testa a conexão Python → SQL Server (`load_stg --check`) |
| `stg` | 4, 5 + evidência `sql/checks/stg_resumo.sql` → `logs/stg_resumo.txt` |
| `ods` | 6 (03, 05, 07) + 7 até o ODS (`@AteCamada = 'ODS'`) + evidência `ods_resumo` |
| `dw` | 6 (04, 06, 07) + 7 completo + evidência `dw_resumo` |
| `export` | 8 |
| `analises` | 8, 9, 10 |
| `glossario` | 12 |
| `todas` | `setup, download, profile, db, check, stg, ods, dw, analises, glossario` |

## Passo a passo

| # | Script / comando | O que faz | Usa | Produz | Próxima |
|---|---|---|---|---|---|
| 1 | `python -m src.extraction.download_ans` | Baixa dados, dicionários (.ods) e notas técnicas (.pdf) das 4 fontes; calcula SHA-256; se o arquivo mudou, move a versão anterior para `_history/` | URLs do FTP PDA da ANS (`SOURCES` no script) | `data/raw/<fonte>/*`, `data/raw/<fonte>/_history/`, `data/raw/manifest.json` (URL, bytes, SHA-256, Last-Modified, data do download), `logs/extraction.log` | 2 |
| 2 | `python -m src.exploration.profile_raw` | Inspeciona os CSVs sem alterá-los: colunas, nulos, períodos, meses faltantes, unicidade do grão, fórmulas oficiais (IGR e TR), cobertura de chaves | `data/raw/*` | `docs/profiling_raw.md`, `data/processed/profiling/profile.json` | 3 |
| 3 | `sql/01_create_schemas.sql` | Cria o banco `ANS_BI`, os schemas `STG`, `ODS`, `DW`, `CTL` e as tabelas e procedures de controle | — | `CTL.Execucao`, `CTL.LogEtapa`, `CTL.ArquivoCarregado`, `CTL.Rejeicao`, `CTL.usp_*` | 4 |
| 4 | `sql/02_create_stg_tables.sql` | Cria as 4 tabelas STG (tudo `NVARCHAR`, nomes originais). O script é **gerado** por `python -m src.loading.load_stg --emit-ddl` a partir dos cabeçalhos reais | cabeçalhos de `data/raw/*` (na geração) | `STG.ANS_Organizacoes_Ativas`, `STG.ANS_Organizacoes_Canceladas`, `STG.ANS_IGR`, `STG.ANS_TR` | 5 |
| 5 | `python -m src.loading.load_stg` | Carga fiel e transacional (TRUNCATE + INSERT + conferência de contagem). Pula arquivo idêntico ao já carregado; bloqueia mudança de layout | `data/raw/*`, `manifest.json`, `.env` | linhas em `STG.*`, `CTL.ArquivoCarregado`, `CTL.LogEtapa`, `logs/loading.log` | 6 |
| 6 | `sql/03` → `04` → `05` → `06` → `07` | 03 tabelas ODS · 04 dimensões e fatos do DW · 05 procedures ODS · 06 procedures DW · 07 `dbo.usp_Pipeline_ANS` | — | objetos `ODS.*`, `DW.*` e procedures `dbo.usp_*` | 7 |
| 7 | `EXEC dbo.usp_Pipeline_ANS` | Verifica a STG → `usp_ODS_Organizacoes` → `usp_ODS_IGR` → `usp_ODS_TR` → `usp_ODS_Validacao` → `usp_DW_Carga` (Dimensões, Fatos, Validação). Interrompe se a reconciliação falhar | `STG.*` | `ODS.Organizacoes`, `ODS.IGR`, `ODS.TR`, `DW.Dim*`, `DW.FatoIGR`, `DW.FatoTR`, `CTL.LogEtapa`, `CTL.Rejeicao` | 8 |
| 8 | `python -m src.analysis.export_dw` | Exporta as dimensões e os fatos do DW para Parquet, conferindo as somas contra o banco | `DW.*` | `data/processed/dw/*.parquet`, `_manifest.json` | 9 |
| 9 | `python -m src.analysis.analises` | Recortes R1 (IGR × TR, 2018–19) e R2 (IGR atual, 12 meses): ranking, índice combinado, funil de Poisson, IQR e z robusto, Spearman/Pearson, Kruskal-Wallis, séries, segmentos, concentração | `data/processed/dw/*.parquet` | `data/processed/analises/*.csv`, `resultados.json`, `reports/figures/*.png` | 10 |
| 10 | `sql/08_create_analise_tables.sql` + `python -m src.analysis.publicar_analises` | Cria e carrega as tabelas de resultados estatísticos no DW | `data/processed/analises/*.csv` | `DW.AnaliseR2Operadora`, `DW.AnaliseR1Operadora` | 11 |
| 12 | `python -m src.semantic.gerar` + `sql/09_glossario.sql` | Valida o catálogo (DAX × definições) e gera o arquivo de medidas, o glossário em Markdown e o script do glossário; carrega `DW.Glossario` | `src/semantic/catalogo.py`, `medidas_dax.json` | `powerbi/medidas.dax`, `docs/glossario.md`, `sql/09_glossario.sql`, `DW.Glossario` | 11 |
| 11 | Power BI Desktop (**parcial**) | Conexão Import em `localhost`/`ANS_BI`; modelo, medidas e layout documentados em `powerbi/`; `.pbix` em montagem manual | `DW.*` | dashboard (em construção) | relatórios (planejado) |

**Fora do fluxo principal:** `sql/checks/*.sql` são consultas de evidência e diagnóstico
(`stg_resumo`, `ods_resumo`, `dw_resumo`, `perf_procedures`, `perf_waits`, `em_execucao`). As saídas validadas estão
versionadas em [`docs/evidencias/`](evidencias/).

**Planejado (não desenvolvido):** relatório técnico, insights executivos, agendamento via SQL Server Agent, testes
automatizados de integração com o banco e preparação para a entrevista.
