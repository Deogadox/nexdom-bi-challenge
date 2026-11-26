# Scripts SQL (SQL Server · banco `ANS_BI`)

Execute **na ordem numérica**, com uma exceção: a carga Python da STG (`python -m src.loading.load_stg`) entra logo
depois do `02`. Todos os scripts são idempotentes (criam só o que não existe; as procedures usam `CREATE OR ALTER`).

```powershell
sqlcmd -S localhost -E -b -I -f 65001 -i sql\01_create_schemas.sql
```
`-E` autenticação Windows · `-b` para no primeiro erro · `-I` `QUOTED_IDENTIFIER ON` · `-f 65001` UTF-8 (acentos).
No SSMS, basta abrir o arquivo e executar (F5): ele já usa essas opções.

| Script | Cria | Observação |
|---|---|---|
| `01_create_schemas.sql` | banco `ANS_BI`; schemas `STG`, `ODS`, `DW`, `CTL`; tabelas e procedures de controle | `RECOVERY SIMPLE` (banco recarregável) |
| `02_create_stg_tables.sql` | `STG.ANS_Organizacoes_Ativas`, `STG.ANS_Organizacoes_Canceladas`, `STG.ANS_IGR`, `STG.ANS_TR` | **gerado** por `python -m src.loading.load_stg --emit-ddl` |
| `03_create_ods_tables.sql` | `ODS.Organizacoes`, `ODS.IGR`, `ODS.TR` | PK no grão, `CHECK` de domínio |
| `04_create_dw_tables.sql` | `DW.Dim*` (6), `DW.FatoIGR`, `DW.FatoTR` | FKs, índices em `SkTempo`, coluna `IGRCalculado` persistida |
| `05_ods_stored_procedures.sql` | `dbo.usp_ODS_Organizacoes`, `usp_ODS_IGR`, `usp_ODS_TR`, `usp_ODS_Validacao` | regras em `docs/regras_de_negocio.md` |
| `06_dw_stored_procedures.sql` | `dbo.usp_DW_Dimensoes`, `usp_DW_Fatos`, `usp_DW_Validacao`, `usp_DW_Carga` | `MERGE` nas dimensões; validação bloqueante |
| `07_pipeline_orchestration.sql` | `dbo.usp_Pipeline_ANS` | `EXEC dbo.usp_Pipeline_ANS;` ou `@AteCamada = 'ODS'` |
| `08_create_analise_tables.sql` | `DW.AnaliseR2Operadora`, `DW.AnaliseR1Operadora` | preenchidas por `python -m src.analysis.publicar_analises` |
| `09_glossario.sql` | `DW.Glossario` (medidas + conceitos) | **gerado** por `python -m src.semantic.gerar` a partir do catálogo |

## `checks/` — evidência e diagnóstico (fora do pipeline)
| Script | Uso |
|---|---|
| `stg_resumo.sql` | contagens da STG, arquivos carregados, log da carga |
| `ods_resumo.sql` | log da última execução, rejeições e alertas por regra, perfil do ODS |
| `dw_resumo.sql` | dimensões, fatos por recorte, mapeamento de segmentos, IGR de 12 meses por segmento |
| `perf_procedures.sql` | tempo e CPU por instrução das procedures ODS (Query Store) |
| `perf_waits.sql` | esperas acumuladas (`RESOURCE_SEMAPHORE`, bloqueios, E/S) e memória da instância |
| `em_execucao.sql` | ao vivo: o que está executando, o que espera e quanta memória pediu |

Exemplo: `sqlcmd -S localhost -E -I -f 65001 -d ANS_BI -W -s "|" -i sql\checks\dw_resumo.sql -o logs\dw_resumo.txt`
