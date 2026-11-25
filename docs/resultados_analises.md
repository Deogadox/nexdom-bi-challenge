# Resultados das análises estatísticas (Fase 7)

Fonte: DW exportado da execução 7 do pipeline (`src/analysis/export_dw.py`), conferido por somas de controle.
Código: `src/analysis/analises.py`. Tabelas: `data/processed/analises/*.csv`. Figuras: `reports/figures/`.
Legenda: **[E]** evidência observada, **[S]** resultado estatístico, **[H]** hipótese (não testada com estes dados).

## Recortes e critérios
| Recorte | Período | Bases | Uso |
|---|---|---|---|
| **R2 — atual** | nov/2025 → out/2026 (12 meses, série vigente) | IGR | ranking atual, porte, outliers, segmentos |
| **R1 — conjunto** | mai/2018 → abr/2019 (últimos 12 meses da janela comum) | IGR + TR | índice combinado, IGR × TR |

- Taxas de período sempre como **soma/soma** (IGR = Σ reclamações / Σ beneficiários × 100 mil; TR = Σ resolvidas / Σ demandas).
- **Elegível** para ranking e outliers: 12 meses com dado e **≥ 5 mil beneficiários médios**. No médico, isso mantém 99,5%
  dos beneficiários. No R1, também é preciso ter **≥ 30 demandas NIP**.
- Comparações sempre **dentro da cobertura**. O IGR médico (52,3) é cerca de 50 vezes o odontológico (1,07).
- **[E]** A série congelada (2015–2019) e a vigente (2021+) têm níveis incompatíveis: cerca de 15 contra 30 a 65 no médico.
  Coincide com a mudança de metodologia, então **não se compara nível entre as séries**.

## Análise 1 — Ranking e indicador combinado
**R2 (IGR atual, assistência médica, 511 elegíveis):**
- **[E]** Os 10 piores IGR são todos de Medicina de Grupo ou Cooperativa Médica, de 318 a 1.189 reclamações por 100 mil
  (AMPLA, SELECT, BLUE COMPANY, …). Os melhores, com 0 a 1,0, são autogestões, filantropias e operadoras de nicho.
  Lista completa em `r2_top10_*_medico.csv`.
- Odontológico: 70 das 183 elegíveis tiveram **zero** reclamações, então o ranking de "melhores" é de empates. Ele é
  apresentado só como lista.

**R1 (IGR × TR, 211 médico-hospitalares elegíveis):** indicador combinado =
`0,5 × Score_IGR + 0,5 × Score_TR`, em que Score_IGR = 100 × (1 − percentil do IGR) e Score_TR = 100 × percentil da TR,
calculados dentro do grupo assistencial.
- Percentil: robusto à assimetria (IGR vai de 0 a mais de 1.000) e coloca os dois indicadores na mesma escala, com sentido coerente.
- Pesos 50/50: sem pesos oficiais, nenhum indicador tem prioridade. **[S]** A ordenação é estável:
  Spearman 0,93 entre 50/50 e 30/70 e 0,92 entre 50/50 e 70/30. No Power BI os pesos ficam ajustáveis.
- **[E]** **49 operadoras críticas** (IGR acima da mediana de 13,8 e TR abaixo da mediana de 91,1%). Piores índices:
  MEDICAL BRASIL (IGR 246, TR 16,6%), AMI, AMENO. Melhores: Unimeds regionais (Londrina, Cascavel, Juiz de Fora,
  Piracicaba), com IGR entre 3 e 6 e TR entre 96% e 100%.
- Odontológico no R1: apenas 9 elegíveis, poucas para um ranking. Fica reportado à parte.

## Análise 2 — Correlação e porte
| Par (médico) | N | Spearman ρ (p) | Pearson r (p) |
|---|---|---|---|
| Beneficiários × reclamações absolutas (R2) | 605 | **0,82** (<0,001) | 0,84, log×log |
| Beneficiários × IGR (R2) | 605 | **0,31** (<0,001) | 0,32, log×log |
| Beneficiários × IGR (R1, 2018–19) | 211 | **−0,38** (<0,001) | −0,36, log×log |
| IGR × TR (R1) | 211 | −0,12 (0,07) | −0,33 (<0,001), log×linear |
| Beneficiários × TR (R1) | 211 | 0,11 (0,13) | 0,21 (0,003), log×linear |

- **[S]** O volume absoluto de reclamações acompanha o porte (ρ 0,82). Por isso o ranking usa o IGR, que é proporcional,
  e não a contagem.
- **[S]** No período atual, operadoras **maiores têm IGR maior** (ρ 0,31). Em 2018–19 era o contrário (ρ −0,38).
  **[H]** Mudança de metodologia, mais reclamações entrando pela NIP nas grandes ou consolidação do mercado.
  Não é testável com estas bases.
- **[S]** IGR × TR: a associação monotônica não é significativa a 5% (Spearman). Pearson é significativo porque a relação
  se concentra na cauda: poucas operadoras com IGR muito alto e TR muito baixa. Conclusão: os indicadores medem coisas
  diferentes, e isso justifica combiná-los.
- **[S]** Porte (R2): Kruskal-Wallis H = 41,5, p < 0,001. IGR mediano: Grande 35,5, Médio 16,7, Pequeno 15,2. O IGR
  agregado dos pequenos (56,1) é alto por causa de poucos outliers extremos.
- Porte e beneficiários vêm da própria base do IGR (definição oficial da ANS); não foi preciso fonte complementar.

## Análise 3 — Outliers
Três métodos, só entre as elegíveis:
1. **Funil de Poisson** com ajuste de sobredispersão (Spiegelhalter, 2005), limites de 99,8%. **[S]** φ = 66 no médico:
   a variação entre operadoras é muito maior do que o acaso explica, e sem o ajuste quase todas seriam "outliers".
2. **IQR** (Q3 + 1,5 × IQR) **dentro do segmento**.
3. **z-score robusto** (mediana/MAD) do log(IGR) dentro do segmento, |z| > 3,5.

**Outlier consistente** = fora do funil **e** discrepante no próprio segmento (IQR ou z).
- **[E]** Médico: 26 acima e 11 abaixo do funil. **20 consistentes para pior**: SELECT, AMPLA, BLUE COMPANY, GEAP,
  Unimed Oeste do Pará, Unimed do Brasil, … (`r2_outliers.csv`). Nenhuma consistente para melhor: as que ficam abaixo
  do funil não destoam dentro do próprio segmento.
- Odontológico: 3 consistentes para pior (φ = 1,4, pouca sobredispersão).

## Análise 4 — Evolução temporal
- **[S]** IGR médico (série vigente, 66 meses): tendência de alta. Spearman com o tempo ρ = 0,63 (p < 0,001); média do
  trimestre inicial 31,1 contra 60,4 no final.
- **[E]** IGR médico jan–out: 2022 36,1 → 2023 53,4 (+48%) → 2024 59,3 (+11%) → 2025 50,6 (−15%) → 2026 55,7 (+10%).
  Comparação sempre entre meses equivalentes, porque 2026 só vai até outubro.
- **[E]** Por segmento (jan–out): **Autogestão 16,6 → 51,7 (3,1 vezes, de 2022 a 2026)**, a maior alta. Seguradoras com
  pico em 2024 (96,3). Medicina de Grupo estável num patamar alto (54 a 66).
- **[S]** IGR odontológico em queda leve (ρ = −0,53).
- **[S]** TR do mercado subiu de 74,9% para 91,3% entre 2015 e 2019 (ρ = 0,94). A TR não assistencial convergiu para a assistencial.
  **[E]** Queda no último mês (2019-10): é compatível com a regra de publicação (mês liberado com cerca de 95% das demandas
  classificadas), então deve ser lida com cautela.

## Análise 5 — Segmentos
| Segmento (R2, médico) | Operadoras | IGR agregado | IGR mediano | P25–P75 |
|---|---|---|---|---|
| Seguradora Especializada em Saúde | 5 | **74,2** | 63,7 | 56–72 |
| Medicina de Grupo | 160 | 60,5 | **38,2** | 16–70 |
| Autogestão | 80 | 50,5 | 13,1 | 5–31 |
| Cooperativa Médica | 239 | 35,5 | 15,4 | 9–29 |
| Filantropia | 27 | 34,2 | 12,1 | 6–29 |

- **[S]** Diferença entre segmentos: Kruskal-Wallis H = 71,4, p < 0,001.
- **[E]** O agregado (visão do beneficiário) e a mediana (operadora típica) divergem. Na Autogestão, o agregado de 50,5
  é puxado pelas grandes (GEAP, Caixa, Postal Saúde, todas outliers). **O dashboard mostra as duas visões.**
- Odontológico: Odontologia de Grupo 1,15 contra Cooperativa Odontológica 0,59 (agregado).
- R1: TR agregada parecida entre os segmentos (89,6% a 91,5%). A diferença entre segmentos está no IGR, não na TR.

## Análise adicional — Concentração
**[E]** As 10 operadoras médicas com mais reclamações concentram **52%** das reclamações e **40,5%** dos beneficiários
(Bradesco, Hapvida NotreDame, SulAmérica, Hapvida, Amil, …). Monitorar poucas operadoras cobre metade do problema.

## Limitações principais
TR indisponível após 2019-10 (substituída pela TIR em 2025). Lacuna do IGR de 2019-05 a 2021-04. Quebra de nível entre
as séries do IGR. Beneficiários contados como vínculos, não pessoas. O IGR mede volume relativo de reclamações, não
gravidade. Correlação não implica causalidade.
