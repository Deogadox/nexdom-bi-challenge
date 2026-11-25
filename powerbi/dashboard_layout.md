# Layout do dashboard — páginas, perguntas e visuais

Tela 16:9 (1280 × 720). Tema: importe `tema_nexdom.json` (Exibir → Temas → Procurar temas).
Cores: **azul `#257de0`** = série principal ou "melhor"; **laranja `#f47230`** = alerta ou "pior";
**cinza `#9c9c9c`** = contexto e referência. Nenhum gráfico com dois eixos y.

**Estrutura comum de todas as páginas**
- Faixa superior: título, `[Texto Período]` e segmentações (Período `DimTempo[AnoMes]` em *entre*,
  **Cobertura** em seleção única, Segmento).
- Rodapé: `[Rótulo Fonte]` e um botão "ⓘ Notas metodológicas" que leva à página 6.
- Sincronize as segmentações de Período e Cobertura entre as páginas 1 a 4 (Exibir → Sincronizar segmentações).
- Padrão da cobertura: *Assistência médica*. Padrão do período: últimos 12 meses (nov/2025 → out/2026).

---

## Página 1 — Visão Executiva
**Pergunta:** como está o mercado agora e onde estão os problemas?

| Visual | Campos / medidas | Observação |
|---|---|---|
| 5 cartões | `[Operadoras com IGR]` · `[IGR]` (rótulo "IGR do mercado") · `[Var % IGR a.a.]` · `[Outliers Críticos (atual)]` · `[% Outliers Críticos]` | No cartão da variação, ícone ▲ laranja / ▼ azul por formatação condicional |
| 2 cartões de texto | `[Pior Operadora (IGR)]` · `[Melhor Operadora (IGR)]` | Subtítulo: "entre operadoras com ≥ 5 mil beneficiários" |
| Linha | Eixo `DimTempo[AnoMes]` (filtro `SerieIGR = VIGENTE`), valor `[IGR]` | Uma série. Linha constante `[IGR Mercado]` em cinza tracejado |
| Barras horizontais | `DimSegmento[Segmento]` × `[IGR]`, cor por `[Cor IGR vs Mercado]` | Ordenado por IGR. Tooltip: `[IGR Mediano (operadoras elegíveis)]`, `[Operadoras Elegíveis]` |
| Tabela Top 10 | `DimOperadora[NomeExibicao]`, `DimSegmento[Segmento]`, `[Beneficiários Médios]`, `[IGR]`, `[Ranking IGR (1 = pior)]` | Filtro do visual: Top N = 10 por `[IGR]`, com `[Operadora Elegível] = 1` |

**Mensagem esperada (dados reais):** IGR médico de 53,9 nos últimos 12 meses, 20 outliers críticos, as Seguradoras
com o maior IGR agregado (74,2) e as 10 maiores operadoras concentrando 52% das reclamações.

## Página 2 — Desempenho das Operadoras
**Pergunta:** quem tem os piores e os melhores indicadores, e quem é crítico em IGR e TR?

| Visual | Campos / medidas | Observação |
|---|---|---|
| Duas tabelas lado a lado | "10 piores" e "10 melhores" IGR (Top N por `[IGR]` desc/asc, só elegíveis) | Colunas: Operadora, Segmento, Porte, `[Beneficiários Médios]`, `[IGR]`, `[IGR Relativo ao Segmento]` (barra de dados) |
| Matriz | Linhas `DimSegmento[Segmento]` → `DimOperadora[NomeExibicao]`; valores `[IGR]`, `[Ranking no Segmento (1 = pior)]`, `[Var % IGR a.a.]` | Ícones na variação |
| Seção "Índice combinado IGR × TR (mai/2018–abr/2019)" com fundo levemente diferente e o aviso "TR não é publicada pela ANS após 2019-10" | | |
| Segmentação do parâmetro | `'Peso IGR'` (controle deslizante) | O usuário testa os pesos |
| Tabela | `NomeExibicao`, `AnaliseR1Operadora[IGR]`, `[TRGeral]`, `[Índice Combinado]`, `[Ranking Índice (1 = melhor)]`, `[Quadrante]` | Filtro de página `GrupoAssistencial = Médico-hospitalar`. Formatação condicional no Quadrante |
| Cartões | `[Operadoras Críticas (IGR alto e TR baixa)]` · `[% Operadoras Críticas]` | |

## Página 3 — Correlações, Porte e Outliers
**Pergunta:** o porte explica as reclamações e a resolutividade? Quem foge do padrão?

| Visual | Campos / medidas | Observação |
|---|---|---|
| Dispersão "funil" | X `AnaliseR2Operadora[BenefMedio]` (escala log), Y `[IGR]`, legenda `[Funil]`, detalhes `NomeExibicao` | Filtro `Elegivel = Verdadeiro`. Cores: Acima = laranja, Abaixo = azul, Dentro = cinza. Tooltip: `Esperado`, `ZFunil`, `LimSupIGR` |
| Dispersão IGR × TR | X `AnaliseR1Operadora[IGR]` (log), Y `[TRGeral]`, legenda `[Quadrante]` | Linhas de mediana (Análise → linha mediana X e Y) formam os quadrantes |
| Colunas | `DimPorte[Porte]` × `[IGR]` e `[IGR Mediano (operadoras elegíveis)]` | **Dois visuais pequenos** (agregado e mediana), não um eixo duplo |
| Tabela de correlações | Importar `data/processed/analises/correlacoes.csv` **ou** caixa de texto com ρ e p | Spearman: beneficiários × reclamações 0,82; × IGR 0,31 (atual); IGR × TR −0,12 (p 0,07, n.s.) |
| Tabela de outliers | `AnaliseR2Operadora` com `OutlierConsistente = Verdadeiro`: Operadora, Segmento, IGR, ZFunil, IQRSegmento | Ordenar por ZFunil desc |

## Página 4 — Análise por Segmento
**Pergunta:** quais segmentos são melhores ou piores, e quão homogêneos são?

| Visual | Campos / medidas | Observação |
|---|---|---|
| Barras agrupadas | `Segmento` × `[IGR]` (agregado) e `[IGR Mediano (operadoras elegíveis)]` | Mostra a diferença entre a visão do beneficiário e a da operadora típica (Autogestão 50,5 contra 13,1) |
| Box plot ou dispersão em faixa | Segmento × IGR por operadora | Sem visual nativo de box plot: use a dispersão com `Segmento` no eixo Y e `[IGR]` no X (log), ou o visual certificado "Box and Whisker" |
| Matriz | Segmento × `DimTempo[Ano]` com `[IGR]` | Formatação condicional (escala azul → laranja). Mostra a Autogestão de 16,6 → 51,7 |
| Cartões por segmento | `[Operadoras Elegíveis]`, `[Outliers Críticos (atual)]` | Múltiplos pequenos (small multiples) por segmento |
| Barras (R1) | `Segmento` × `[TR]` com o filtro de página `FlJanelaComumIGRTR = 1` | TR parecida entre segmentos (89,6% a 91,5%) |

## Página 5 — Evolução Temporal
**Pergunta:** como os indicadores evoluíram e o que mudou?

| Visual | Campos / medidas | Observação |
|---|---|---|
| Linha IGR | `DimTempo[DataMes]` × `[IGR]`, legenda `DimTempo[SerieIGR]` | Congelada em cinza, vigente em azul. **Anotação na lacuna 2019-05 → 2021-04** e o aviso "níveis não comparáveis entre séries (mudança de metodologia)" |
| Linha TR | `DimTempo[DataMes]` × `[TR]`, legenda `DimNatureza[Natureza]` | 2015–2019. De 74,9% para 91,3%. Nota sobre o último mês (regra de 95% classificadas) |
| Colunas | `DimTempo[Ano]` × `[IGR]` com filtro `Mes ≤ 10` | Rótulo "jan–out de cada ano (meses equivalentes)"; tooltip `[Var % IGR a.a.]` |
| Linhas pequenas | `DimTempo[DataMes]` × `[IGR]` com small multiples por `Segmento` | Tendência por segmento sem poluir um só gráfico |
| Cartões | `[Var % IGR a.a.]` · `[Var TR a.a. (p.p.)]` | |

## Página 6 — Notas metodológicas (texto)
Fontes e datas, definição do IGR e da TR, recortes R1 e R2, critério de elegibilidade, o índice combinado (metodologia do
projeto, pesos ajustáveis), as duas definições de "crítica" e as limitações (TR até 2019, lacuna e quebra do IGR,
vínculos ≠ pessoas). Base: `docs/resultados_analises.md`.

---

### Tooltips personalizados (página de dica de ferramenta, 320 × 240)
Operadora: `NomeExibicao`, Segmento, Porte, `[Beneficiários Médios]`, `[IGR]`, `[IGR do Segmento]`,
`[IGR Relativo ao Segmento]` e um minigráfico de linha `[IGR]` por mês. Use nas páginas 1 a 4.

### Checklist de qualidade
- [ ] Cobertura em seleção única em toda página com IGR (`[Aviso Cobertura]` num cartão vermelho se violar)
- [ ] Nenhum ranking sem o filtro de elegibilidade
- [ ] TR e índice combinado sempre rotulados "mai/2018–abr/2019"
- [ ] Valores de referência do `powerbi/README.md` conferidos
- [ ] Títulos em forma de pergunta ou conclusão (ex.: "Seguradoras têm o maior IGR agregado")
