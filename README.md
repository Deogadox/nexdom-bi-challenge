# NEXDOM | Desafio Técnico — Analista de BI Pleno
### Análise integrada de operadoras, IGR e Taxa de Resolutividade (ANS)

> Status: **Fase 1 concluída · Fase 2 em andamento** (scripts de coleta e profiling prontos e testados; aguardando download completo).

## Arquitetura
`Python (coleta, carga STG, orquestração) → SQL Server STG → ODS → DW (Stored Procedures) → Power BI`. Detalhes em [docs/arquitetura.md](docs/arquitetura.md).

## Objetivo
Integrar três bases públicas da ANS — cadastro de operadoras, Índice Geral de Reclamações (metodologia 2023)
e Taxa de Resolutividade — para ranquear operadoras, medir a relação entre porte, reclamações e resolutividade,
identificar outliers, avaliar a evolução temporal e comparar segmentos (modalidades).

## Como executar

```powershell
python -m venv .venv; .venv\Scripts\Activate.ps1
pip install -r requirements.txt
python -m src.extraction.download_ans      # 1. coleta (data/raw + manifest.json)
python -m src.exploration.profile_raw      # 2. profiling (docs/profiling_raw.md)
python -m pytest -q                        # testes
```

## Documentação
- [Fontes e estrutura dos dados](docs/fontes_dados.md)
- [Arquitetura técnica](docs/arquitetura.md)
- Profiling das bases: `docs/profiling_raw.md` (gerado)

## Plano de execução

| Fase | Entrega | Status |
|---|---|---|
| 1. Entendimento e planejamento | Requisitos, fontes oficiais, metodologias IGR/TR, arquitetura | ✅ |
| 2. Coleta e exploração | `download_ans.py`, `profile_raw.py`, profiling das bases completas | 🔄 |
| 3. Ambiente | SQL Server local, ODBC, `.env`, schemas `STG/ODS/DW/CTL` | ⏳ |
| 4. Carga STG | `load_stg.py` (texto + metadados de controle) | ⏳ |
| 5. ODS | `usp_ODS_*` com validação, rejeições e logs | ⏳ |
| 6. DW | Dimensões, fatos, `usp_Pipeline_ANS` | ⏳ |
| 7. Análises estatísticas | Ranking combinado, Spearman/Pearson, outliers (IQR/z robusto), séries, segmentos | ⏳ |
| 8. DAX | Medidas documentadas | ⏳ |
| 9. Dashboard | 5 páginas Power BI | ⏳ |
| 10–11. Relatórios | Técnico (≤5 p.) e Insights executivos (≤1 p.) | ⏳ |
| 12. Testes | Qualidade, integridade, reconciliação com valores publicados | ⏳ |
| 13. Git | Publicação no GitHub | ⏳ |
| 14. Entrevista | Roteiro + 20 perguntas + simulação | ⏳ |

## Perguntas de negócio → análise
| Pergunta | Análise |
|---|---|
| Quem tem mais reclamações proporcionalmente ao porte? | IGR (já é por 100 mil beneficiários), estratificado por porte |
| Alto IGR e baixa TR? | Matriz IGR × TR com quadrantes por mediana do grupo comparável |
| Porte × reclamações × resolutividade | Spearman (distribuições assimétricas) + Pearson em log, mapa de calor |
| Outliers | IQR e z-score robusto (mediana/MAD) dentro de segmento e porte |
| Evolução | Séries mensais e janelas móveis de 12 meses (somas de numerador/denominador) |
| Segmentos | Média, mediana, distribuição e ranking por modalidade |
