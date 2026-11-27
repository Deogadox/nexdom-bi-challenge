# Layout do dashboard — páginas, perguntas e visuais

Tela 16:9 (1280 × 720). Tema: importe `tema_nexdom.json` (Exibir → Temas → Procurar temas).
Cores (identidade NEXDOM): **verde Excelência `#045F51`** = série principal ou "melhor"; **laranja Impulso `#FF7F40`** =
alerta ou "pior"; **cinza `#8A8590`** = contexto e referência; texto `#06262D`; fundo da página `#E5E1E6` com cartões
brancos. `#6CCA98` (Saúde) só como fundo/realce, nunca linha fina ou texto em fundo branco (contraste 2:1).
`#1F1645` (Confiança) para uma 2ª série quando precisar. Validado: `#045F51` × `#FF7F40` distinguíveis também para
daltônicos (ΔE 21,9); o laranja tem contraste 2,5:1 no branco, então barras laranja levam rótulo de dados.
Nenhum gráfico com dois eixos y.

**Estrutura comum de todas as páginas**
- Faixa superior: título, `[Texto Período]` e segmentações (Período `D_Tempo[AnoMes]` em *entre*,
  **Cobertura** em seleção única, Segmento).
- Rodapé: `[Rótulo Fonte]` e um botão "ⓘ Notas metodológicas" que leva à página 6.
- Sincronize as segmentações de Período e Cobertura entre as páginas 1 a 4 (Exibir → Sincronizar segmentações).
- Padrão da cobertura: *Assistência médica*. Padrão do período: últimos 12 meses (nov/2025 → out/2026).

---

## Estrutura revisada (sem limite de páginas)

Cada página responde **uma pergunta** e usa **um recorte** de dados. As páginas não misturam o recorte atual (IGR
nov/2025–out/2026) com o de 2018–19 (IGR × TR):

| # | Página | Pergunta | Recorte |
|---|---|---|---|
| 1 | Visão Executiva | Como está o mercado e onde estão os problemas? | atual |
| 2 | Impacto das Operadoras | Quem gera mais reclamações além do esperado? Quem se destaca em cada segmento? | atual |
| 3 | IGR × Resolutividade | Quem tem IGR alto e TR baixa? Ranking combinado (P2, A1) | mai/2018–abr/2019 |
| 4 | Porte, Correlações e Outliers | O porte explica? Quem foge do padrão? (P3, A2, A3) | atual (+ correlações R1) |
| 5 | Segmentos | Quais segmentos são melhores/piores e quão homogêneos? (A5) | atual |
| 6 | Evolução Temporal | Como os indicadores evoluíram? (A4) | 2015–2026 |
| 7 | Ficha da Operadora (drill-through) | Tudo sobre uma operadora: histórico, segmento, TR | todos |
| 8 | Notas metodológicas | — | — |
| 9 | Glossário | — | — |

As seções abaixo detalham o conteúdo; onde a numeração antiga diverge, vale esta tabela.

## Página 1 — Visão Executiva
**Pergunta:** como está o mercado agora e onde estão os problemas?

| Visual | Campos / medidas | Observação |
|---|---|---|
| 5 cartões | `[Operadoras com IGR]` · `[IGR]` (rótulo "IGR do mercado") · `[Var % IGR a.a.]` · `[Outliers Críticos (atual)]` · `[% Outliers Críticos]` | No cartão da variação, ícone ▲ laranja / ▼ verde por formatação condicional |
| 2 cartões de texto | `[Pior Operadora (IGR)]` · `[Melhor Operadora (IGR)]` | Subtítulo: "entre operadoras com ≥ 5 mil beneficiários" |
| Linha | Eixo `D_Tempo[DataMes]` (contínuo; filtro do visual `SerieIGR = VIGENTE`, fora da legenda), valor `[IGR]` | Uma série. Referência opcional: painel Análise → Linha de média |
| Barras horizontais | `D_Segmento[Segmento]` × `[IGR]`, cor por `[Cor IGR vs Mercado]` | Ordenado por IGR. Tooltip: `[IGR Mediano (operadoras elegíveis)]`, `[Operadoras Elegíveis]` |
| Tabela Top 10 | `D_Operadora[NomeExibicao]`, `D_Segmento[Segmento]`, `[Beneficiários Médios]`, `[IGR]`, `[Ranking IGR (1 = pior)]` | Filtro do visual: `[Ranking IGR (1 = pior)]` menor ou igual a 10 (não usar Top N). Ordenar pelo ranking, crescente. Totais desativados |

**Mensagem esperada (dados reais):** IGR médico de 53,9 nos últimos 12 meses, 20 outliers críticos, as Seguradoras
com o maior IGR agregado (74,2) e as 10 maiores operadoras concentrando 52% das reclamações.

## Página 2 — Impacto das Operadoras (recorte atual)
**Pergunta:** quais operadoras geram mais reclamações *além do esperado* para o seu porte, e quem se destaca em cada
segmento? A página 1 já mostra o ranking por taxa (IGR); aqui o foco é o **impacto em volume** e o **destaque por segmento**.

| Visual | Campos / medidas | Observação |
|---|---|---|
| 3 cartões | `[Operadoras Elegíveis]` · `[IGR Mediano (operadoras elegíveis)]` · `[IGR]` ("IGR do mercado") | 511 · 18,21 · 53,86 |
| Barras horizontais "Reclamações acima do esperado" | Eixo `D_Operadora[NomeExibicao]`, valor `[Excesso de Reclamações (atual)]` | Filtro do visual: N superior 15 por `[Excesso de Reclamações (atual)]`. Cor `#FF7F40`, rótulos de dados. Tooltip: `Segmento`, `[IGR]`, `[Beneficiários Médios]` |
| Barras horizontais "Reclamações abaixo do esperado" | Igual, com N **inferior** 15 | Cor `#045F51`. Valores negativos (barras para a esquerda) |
| Tabela "Destaques por segmento" (5 linhas) | `D_Segmento[Segmento]`, `[Operadoras Elegíveis]`, `[IGR]`, `[IGR Mediano (operadoras elegíveis)]`, `[Pior Operadora (IGR)]`, `[Melhor Operadora (IGR)]` | Sem hierarquia. Substitui a matriz com expansão (nomes demais) |

**Esperado** = reclamações que a operadora teria com o IGR do mercado (52,33, só elegíveis) e os próprios beneficiários.
O total do excesso é 0 por construção; o positivo soma 83.050 em 96 operadoras, e as 15 primeiras respondem por 58.890 (71%).
Valores: SulAmérica +10.400 · Bradesco +7.709 · SELECT +7.521 · Hapvida NotreDame SP/RJ +7.518 · GEAP +5.611;
abaixo: Hapvida −3.972 · Unimed Porto Alegre −2.436 · IPASGO −2.325 · APPAI −2.265.

## Página 3 — Correlações, Porte e Outliers
**Pergunta:** o porte explica as reclamações e a resolutividade? Quem foge do padrão?

| Visual | Campos / medidas | Observação |
|---|---|---|
| Dispersão "funil" | X `Anl_R2Operadora[BenefMedio]` (escala log), Y `[IGR]`, legenda `[Funil]`, detalhes `NomeExibicao` | Filtro `Elegivel = Verdadeiro`. Cores: Acima = laranja, Abaixo = verde, Dentro = cinza. Tooltip: `Esperado`, `ZFunil`, `LimSupIGR` |
| Dispersão IGR × TR | X `Anl_R1Operadora[IGR]` (log), Y `[TRGeral]`, legenda `[Quadrante]` | Linhas de mediana (Análise → linha mediana X e Y) formam os quadrantes |
| Colunas | `D_Porte[Porte]` × `[IGR]` e `[IGR Mediano (operadoras elegíveis)]` | **Dois visuais pequenos** (agregado e mediana), não um eixo duplo |
| Tabela de correlações | Importar `data/processed/analises/correlacoes.csv` **ou** caixa de texto com ρ e p | Spearman: beneficiários × reclamações 0,82; × IGR 0,31 (atual); IGR × TR −0,12 (p 0,07, n.s.) |
| Tabela de outliers | `Anl_R2Operadora` com `OutlierConsistente = Verdadeiro`: Operadora, Segmento, IGR, ZFunil, IQRSegmento | Ordenar por ZFunil desc |

## Página 4 — Análise por Segmento
**Pergunta:** quais segmentos são melhores ou piores, e quão homogêneos são?

| Visual | Campos / medidas | Observação |
|---|---|---|
| Barras agrupadas | `Segmento` × `[IGR]` (agregado) e `[IGR Mediano (operadoras elegíveis)]` | Mostra a diferença entre a visão do beneficiário e a da operadora típica (Autogestão 50,5 contra 13,1) |
| Box plot ou dispersão em faixa | Segmento × IGR por operadora | Sem visual nativo de box plot: use a dispersão com `Segmento` no eixo Y e `[IGR]` no X (log), ou o visual certificado "Box and Whisker" |
| Matriz | Segmento × `D_Tempo[Ano]` com `[IGR]` | Formatação condicional (escala verde → laranja). Mostra a Autogestão de 16,6 → 51,7 |
| Cartões por segmento | `[Operadoras Elegíveis]`, `[Outliers Críticos (atual)]` | Múltiplos pequenos (small multiples) por segmento |
| Barras (R1) | `Segmento` × `[TR]` com o filtro de página `FlJanelaComumIGRTR = 1` | TR parecida entre segmentos (89,6% a 91,5%) |

## Página 5 — Evolução Temporal
**Pergunta:** como os indicadores evoluíram e o que mudou?

| Visual | Campos / medidas | Observação |
|---|---|---|
| Linha IGR | `D_Tempo[DataMes]` × `[IGR]`, legenda `D_Tempo[SerieIGR]` | Congelada em cinza, vigente em verde `#045F51`. **Anotação na lacuna 2019-05 → 2021-04** e o aviso "níveis não comparáveis entre séries (mudança de metodologia)" |
| Linha TR | `D_Tempo[DataMes]` × `[TR]`, legenda `D_Natureza[Natureza]` | 2015–2019. De 74,9% para 91,3%. Nota sobre o último mês (regra de 95% classificadas) |
| Colunas | `D_Tempo[Ano]` × `[IGR]` com filtro `Mes ≤ 10` | Rótulo "jan–out de cada ano (meses equivalentes)"; tooltip `[Var % IGR a.a.]` |
| Linhas pequenas | `D_Tempo[DataMes]` × `[IGR]` com small multiples por `Segmento` | Tendência por segmento sem poluir um só gráfico |
| Cartões | `[Var % IGR a.a.]` · `[Var TR a.a. (p.p.)]` | |

## Página 6 — Notas metodológicas (texto)
Fontes e datas, definição do IGR e da TR, recortes R1 e R2, critério de elegibilidade, o índice combinado (metodologia do
projeto, pesos ajustáveis), as duas definições de "crítica" e as limitações (TR até 2019, lacuna e quebra do IGR,
vínculos ≠ pessoas). Base: `docs/resultados_analises.md`.

## Página 7 — Glossário
**Pergunta:** o que significa cada número do dashboard e como ele foi calculado?

| Visual | Campos | Observação |
|---|---|---|
| Segmentação (botões) | `Glossario[Tipo]` (Medida / Conceito) | |
| Segmentação (lista suspensa) | `Glossario[Pasta]` | 0 Parâmetros … 7 UX, Conceitos |
| Segmentação de texto | `Glossario[Termo]` | visual de pesquisa ("Text filter", certificado) ou lista com busca habilitada |
| Tabela | `Termo`, `Definicao`, `Calculo`, `Unidade`, `Sentido`, `Observacao` | Ordenada por `Ordem`; quebra de linha ativa; largura maior para Definição e Cálculo |
| Cartão de várias linhas (opcional) | `ExpressaoDAX` do termo selecionado | Mostra o código da medida escolhida |

A tabela `Glossario` não tem relacionamentos, então os filtros das outras páginas não a afetam. O conteúdo vem do
catálogo único (`src/semantic/catalogo.py`): o glossário mostra exatamente as medidas do modelo.
Na página 6, coloque um botão "Ver glossário" que leva a esta página.

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
