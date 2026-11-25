# Limitações

## Das bases oficiais
| Limitação | Impacto | Tratamento no projeto |
|---|---|---|
| **TR publicada só até 2019-10** (a ANS passou a usar a TIR em 2025) | Não há resolutividade atual | Dois recortes: IGR × TR em mai/2018–abr/2019 (R1) e IGR atual em nov/2025–out/2026 (R2), sempre rotulados |
| **Lacuna do IGR de 2019-05 a 2021-04** | Série incompleta | `DimTempo.FlIGRDisponivel`; nenhuma interpolação ou série artificial |
| **Quebra de nível entre a série congelada e a vigente do IGR** (≈ 15 contra 30–65 no médico) | Níveis não comparáveis | Tendência e variação calculadas só dentro da série vigente |
| IGR inclui demandas em andamento e é recalculado retroativamente | Valores podem mudar entre publicações | `manifest.json`, `_history/` e `CTL.ArquivoCarregado` registram a versão usada |
| Último mês da TR (2019-10) com queda | Possível efeito da regra de publicação (mês liberado com cerca de 95% classificado) | Mencionado como ressalva |
| Beneficiários = vínculos, não pessoas | Uma pessoa com dois planos conta duas vezes | Inerente à métrica oficial |
| IGR mede volume relativo de reclamações, não gravidade | Não diferencia reclamações simples de graves | Explicitado nas conclusões |
| CADOP é um retrato atual, sem histórico | A modalidade de uma operadora cancelada é a última registrada | `DimOperadora` em SCD tipo 1 |
| Administradoras de benefícios não têm IGR (nota técnica) | Fora dos rankings de IGR | Aparecem só na TR |
| Modalidades legadas ("Seguradora", "Administradora") nas canceladas | Agrupamento por segmento | Mapeadas para o segmento atual com `FlModalidadeLegada = 1` |
| IGR odontológico muito baixo (58% das operadoras com zero reclamações em 12 meses) | Ranking de "melhores" com empates | Lista apresentada sem ordenação forte; análises sempre por cobertura |

## Metodológicas
- **Índice combinado** (percentis de IGR e TR, pesos 50/50 ajustáveis) é uma metodologia do projeto, não um indicador oficial.
- **Volume mínimo** (≥ 5 mil beneficiários médios, ≥ 30 demandas NIP) exclui operadoras pequenas dos rankings. Elas
  continuam nas tabelas com `Elegivel = 0`.
- **Correlação não implica causalidade.** A inversão da relação porte × IGR entre 2018–19 e 2025–26 tem hipóteses
  (metodologia, canais de reclamação, consolidação do mercado) que estas bases não permitem testar.
- O funil de Poisson usa a taxa das operadoras elegíveis como referência e um único fator de sobredispersão por cobertura.

## Do ambiente e do projeto
- Execução validada em uma instância local (SQL Server 2022 Developer). Não há agendamento configurado.
- Os testes automatizados (`tests/`) cobrem leitura, parsing, fórmulas e geração de DDL, sem banco. A validação do banco
  é feita pelas procedures `usp_ODS_Validacao` e `usp_DW_Validacao` e pelos scripts de `sql/checks/`.
- O dashboard Power BI está em montagem; relatório técnico e insights executivos ainda não foram produzidos.
