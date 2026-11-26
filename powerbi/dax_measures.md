# Medidas DAX

**Tabela de medidas:** Página Inicial → *Inserir dados* → nome `Medidas` → *Carregar* (sem preencher). Crie todas as
medidas nela (botão direito → *Nova medida*) e, depois da primeira, exclua a `Coluna1`. A tabela vira tabela de
medidas (ícone de calculadora). Pastas de exibição: Exibição de modelo → selecione as medidas → *Propriedades →
Pasta de exibição* com os nomes das seções abaixo (`0 Parâmetros`, `1 IGR` … `7 UX`). As tabelas dos parâmetros
continuam existindo, porque a segmentação depende delas; só as medidas "Valor" vão para `Medidas`. Convenções: taxa = **soma/soma** (nunca a média de taxas), `DIVIDE` em toda divisão e variáveis
com prefixo `_`.

Referências oficiais: IGR = reclamações ÷ beneficiários × 100 mil (**maior = pior**);
TR = (Inativa + NP + RVE) ÷ (Inativa + NP + RVE + Núcleo) (**maior = melhor**).

---

## 0. Parâmetros de cenário  (pasta `0 Parâmetros`; Modelagem → Novo parâmetro → Intervalo numérico)

| Parâmetro | Intervalo | Padrão | Uso |
|---|---|---|---|
| `Peso IGR` | 0 a 1, passo 0,05 | 0,5 | peso do IGR no índice combinado (TR = 1 − peso) |
| `Benef Mínimo` | 0 a 100.000, passo 1.000 | 5.000 | volume mínimo para ranking |

O Power BI cria as tabelas e as medidas `Valor` automaticamente. Renomeie-as para os nomes abaixo, ou ajuste as referências.

```DAX
Peso IGR Valor = SELECTEDVALUE ( 'Peso IGR'[Peso IGR], 0.5 )
Benef Mínimo Valor = SELECTEDVALUE ( 'Benef Mínimo'[Benef Mínimo], 5000 )
```

---

## 1. Base · IGR  (pasta `1 IGR`)

```DAX
Reclamações = SUM ( F_IGR[QtdReclamacoes] )

Beneficiários (soma mensal) = SUM ( F_IGR[QtdBeneficiarios] )

Meses com IGR = DISTINCTCOUNT ( F_IGR[SkTempo] )

Beneficiários Médios =
DIVIDE ( [Beneficiários (soma mensal)], [Meses com IGR] )

IGR =
DIVIDE ( [Reclamações], [Beneficiários (soma mensal)] ) * 100000

IGR Mercado =
CALCULATE ( [IGR], REMOVEFILTERS ( D_Operadora ), REMOVEFILTERS ( D_Segmento ), REMOVEFILTERS ( D_Porte ) )

Operadoras com IGR =
CALCULATE ( DISTINCTCOUNT ( F_IGR[SkOperadora] ), F_IGR[QtdBeneficiarios] > 0 )
```
- `IGR` vale para qualquer recorte: operadora, segmento, porte, mês ou período. Somar reclamações e beneficiários
  antes de dividir equivale à definição oficial para períodos (média de reclamações ÷ média de beneficiários).
- `Beneficiários Médios` é a média mensal no período e é o critério de porte e de volume mínimo.
- `IGR Mercado` mantém os filtros de tempo e cobertura e ignora operadora, segmento e porte. É a linha de referência dos gráficos.

## 2. Base · TR  (pasta `2 TR`)

```DAX
Demandas NIP =
VAR _ApenasTotal = NOT ISFILTERED ( D_Natureza[Natureza] )
RETURN
    IF (
        _ApenasTotal,
        CALCULATE ( SUM ( F_TR[Denominador] ), D_Natureza[FlTotal] = TRUE () ),
        CALCULATE ( SUM ( F_TR[Denominador] ), KEEPFILTERS ( D_Natureza[FlTotal] = FALSE () ) )
    )

Demandas Resolvidas =
VAR _ApenasTotal = NOT ISFILTERED ( D_Natureza[Natureza] )
RETURN
    IF (
        _ApenasTotal,
        CALCULATE ( SUM ( F_TR[Numerador] ), D_Natureza[FlTotal] = TRUE () ),
        CALCULATE ( SUM ( F_TR[Numerador] ), KEEPFILTERS ( D_Natureza[FlTotal] = FALSE () ) )
    )

TR = DIVIDE ( [Demandas Resolvidas], [Demandas NIP] )
```
- **Por que o `IF`:** a natureza `Geral` já é a soma de Assistencial e Não Assistencial (validado: 0 divergências).
  Sem filtro de natureza, a medida usa só a `Geral`. Com filtro ou com a natureza no eixo, usa só A e N. Assim nunca
  conta em dobro. No eixo, a linha "Geral" fica vazia e o total do visual é A + N.
- `TR` com formato percentual. Só há dados de 2015-01 a 2019-10.

## 3. Tempo  (pasta `3 Tempo`)

```DAX
Meses no Período =
CALCULATE (
    DISTINCTCOUNT ( F_IGR[SkTempo] ),
    REMOVEFILTERS ( D_Operadora ), REMOVEFILTERS ( D_Segmento ), REMOVEFILTERS ( D_Porte )
)

IGR Ano Anterior =
VAR _MesesAnt =
    SELECTCOLUMNS ( VALUES ( D_Tempo[SkTempo] ), "SkTempo", D_Tempo[SkTempo] - 100 )
RETURN
    CALCULATE ( [IGR], REMOVEFILTERS ( D_Tempo ), TREATAS ( _MesesAnt, D_Tempo[SkTempo] ) )

Var % IGR a.a. =
VAR _MesesAnt =
    SELECTCOLUMNS ( VALUES ( D_Tempo[SkTempo] ), "SkTempo", D_Tempo[SkTempo] - 100 )
VAR _QtdAtual = [Meses no Período]
VAR _QtdAnt =
    CALCULATE ( [Meses no Período], REMOVEFILTERS ( D_Tempo ), TREATAS ( _MesesAnt, D_Tempo[SkTempo] ) )
VAR _Ant = [IGR Ano Anterior]
RETURN
    IF ( _QtdAtual = _QtdAnt && NOT ISBLANK ( _Ant ), DIVIDE ( [IGR] - _Ant, _Ant ) )

TR Ano Anterior =
VAR _MesesAnt =
    SELECTCOLUMNS ( VALUES ( D_Tempo[SkTempo] ), "SkTempo", D_Tempo[SkTempo] - 100 )
RETURN
    CALCULATE ( [TR], REMOVEFILTERS ( D_Tempo ), TREATAS ( _MesesAnt, D_Tempo[SkTempo] ) )

Var TR a.a. (p.p.) =
VAR _Ant = [TR Ano Anterior]
RETURN IF ( NOT ISBLANK ( _Ant ) && NOT ISBLANK ( [TR] ), ( [TR] - _Ant ) * 100 )
```
- `D_Tempo` não é tabela de datas, então o "ano anterior" é o `SkTempo − 100` (AAAAMM). Funciona para qualquer
  seleção de meses.
- `Var % IGR a.a.` só retorna valor quando o período anterior tem **o mesmo número de meses com dado**. Isso evita
  comparar 2026 (jan–out) com 2025 inteiro e evita atravessar a lacuna de 2019-05 a 2021-04.
- Variação da TR em **pontos percentuais**, não em %.

## 4. Elegibilidade e rankings  (pasta `4 Ranking`)

```DAX
Operadora Elegível =
IF (
    [Meses com IGR] = [Meses no Período] && [Beneficiários Médios] >= [Benef Mínimo Valor],
    1, 0
)

Operadoras Elegíveis =
COUNTROWS ( FILTER ( VALUES ( D_Operadora[SkOperadora] ), [Operadora Elegível] = 1 ) )

IGR Mediano (operadoras elegíveis) =
MEDIANX ( FILTER ( VALUES ( D_Operadora[SkOperadora] ), [Operadora Elegível] = 1 ), [IGR] )

Ranking IGR (1 = pior) =
IF (
    [Operadora Elegível] = 1,
    RANKX (
        FILTER ( ALLSELECTED ( D_Operadora[NomeExibicao] ), [Operadora Elegível] = 1 ),
        [IGR], , DESC, DENSE
    )
)

Ranking IGR (1 = melhor) =
IF (
    [Operadora Elegível] = 1,
    RANKX (
        FILTER ( ALLSELECTED ( D_Operadora[NomeExibicao] ), [Operadora Elegível] = 1 ),
        [IGR], , ASC, DENSE
    )
)

IGR do Segmento =
VAR _Seg = SELECTEDVALUE ( D_Operadora[SkSegmento] )
RETURN
    CALCULATE ( [IGR], REMOVEFILTERS ( D_Operadora ), D_Operadora[SkSegmento] = _Seg )

IGR Relativo ao Segmento =
DIVIDE ( [IGR], [IGR do Segmento] )

Ranking no Segmento (1 = pior) =
VAR _Seg = SELECTEDVALUE ( D_Operadora[SkSegmento] )
RETURN
    IF (
        [Operadora Elegível] = 1,
        RANKX (
            FILTER (
                CALCULATETABLE (
                    VALUES ( D_Operadora[NomeExibicao] ),
                    ALLSELECTED ( D_Operadora ),
                    D_Operadora[SkSegmento] = _Seg
                ),
                [Operadora Elegível] = 1
            ),
            [IGR], , DESC, DENSE
        )
    )

Pior Operadora (IGR) =
CONCATENATEX (
    TOPN ( 1, FILTER ( VALUES ( D_Operadora[NomeExibicao] ), [Operadora Elegível] = 1 ), [IGR], DESC ),
    D_Operadora[NomeExibicao], ", "
)

Melhor Operadora (IGR) =
CONCATENATEX (
    TOPN ( 1, FILTER ( VALUES ( D_Operadora[NomeExibicao] ), [Operadora Elegível] = 1 ),
           [IGR], ASC, [Beneficiários Médios], DESC ),
    D_Operadora[NomeExibicao], ", "
)
```
- **Elegível:** presente em todos os meses do período e com média ≥ `Benef Mínimo` (padrão 5 mil). Na análise, isso
  removeu taxas instáveis (ex.: uma operadora com 1 beneficiário e IGR 9.100.000) e manteve 99,5% dos beneficiários.
- Rankings com `ALLSELECTED`: respeitam as segmentações (cobertura, segmento, período) e ignoram a linha do visual.
- `IGR Relativo ao Segmento` acima de 1 = pior que o próprio segmento. Responde "quem destoa do seu segmento".
- `Melhor Operadora` desempata pelo maior porte: muitas operadoras têm IGR = 0.
- **Use sempre com uma única cobertura filtrada** (ver `Aviso Cobertura`).

## 5. Concentração  (pasta `5 Concentração`)

```DAX
% das Reclamações =
DIVIDE ( [Reclamações], CALCULATE ( [Reclamações], ALLSELECTED ( D_Operadora ) ) )

% Acumulado das Reclamações =
VAR _Atual = [Reclamações]
VAR _Tab =
    ADDCOLUMNS ( ALLSELECTED ( D_Operadora[NomeExibicao] ), "@Rec", [Reclamações] )
RETURN
    DIVIDE ( SUMX ( FILTER ( _Tab, [@Rec] >= _Atual ), [@Rec] ), SUMX ( _Tab, [@Rec] ) )
```
- Gráfico de Pareto. Na análise, as 10 maiores concentram 52% das reclamações e 40,5% dos beneficiários.

## 6. Resultados estatísticos  (pasta `6 Estatística`, tabelas `Anl_R2Operadora` / `Anl_R1Operadora`)

```DAX
Operadoras Elegíveis (R2) =
CALCULATE ( COUNTROWS ( Anl_R2Operadora ), Anl_R2Operadora[Elegivel] = TRUE () )

Outliers Críticos (atual) =
CALCULATE (
    COUNTROWS ( Anl_R2Operadora ),
    Anl_R2Operadora[OutlierConsistente] = TRUE (),
    Anl_R2Operadora[Funil] = "Acima (pior)"
)

% Outliers Críticos =
DIVIDE ( [Outliers Críticos (atual)], [Operadoras Elegíveis (R2)] )

Excesso de Reclamações (atual) =
CALCULATE (
    SUM ( Anl_R2Operadora[Reclamacoes] ) - SUM ( Anl_R2Operadora[Esperado] ),
    Anl_R2Operadora[Elegivel] = TRUE ()
)

Índice Combinado =
VAR _W = [Peso IGR Valor]
RETURN
    AVERAGEX (
        FILTER ( Anl_R1Operadora, Anl_R1Operadora[Elegivel] = TRUE () ),
        _W * Anl_R1Operadora[ScoreIGR] + ( 1 - _W ) * Anl_R1Operadora[ScoreTR]
    )

Ranking Índice (1 = melhor) =
IF (
    NOT ISBLANK ( [Índice Combinado] ),
    RANKX (
        FILTER ( ALLSELECTED ( D_Operadora[NomeExibicao] ), NOT ISBLANK ( [Índice Combinado] ) ),
        [Índice Combinado], , DESC, DENSE
    )
)

Operadoras Críticas (IGR alto e TR baixa) =
CALCULATE (
    COUNTROWS ( Anl_R1Operadora ),
    Anl_R1Operadora[Quadrante] = "Crítico: IGR alto e TR baixa"
)

% Operadoras Críticas =
DIVIDE (
    [Operadoras Críticas (IGR alto e TR baixa)],
    CALCULATE ( COUNTROWS ( Anl_R1Operadora ), Anl_R1Operadora[Elegivel] = TRUE () )
)
```
- **Índice combinado**: os scores são percentis dentro do grupo assistencial (100 = melhor), já calculados no DW,
  com IGR invertido para que maior seja sempre melhor. O DAX só aplica os pesos do parâmetro, então o usuário testa
  cenários. A análise mostrou ordenação estável: Spearman ≥ 0,92 entre os pesos 30/70, 50/50 e 70/30.
  **É uma metodologia do projeto, não um indicador oficial da ANS.**
- O ranking do índice deve ser lido **dentro de um grupo assistencial**: filtre `D_Segmento[GrupoAssistencial]`.
- `Excesso de Reclamações` = observado − esperado à taxa do mercado. Mostra onde o volume "a mais" está concentrado
  e serve para priorizar ações.
- "Críticas" têm duas definições, sempre rotuladas no visual:
  - **atual** (2025–26): outlier consistente no funil de Poisson **e** dentro do próprio segmento;
  - **R1** (2018–19): IGR acima da mediana **e** TR abaixo da mediana do grupo.

## 7. Apoio ao layout  (pasta `7 UX`)

```DAX
Aviso Cobertura =
IF (
    HASONEVALUE ( D_Cobertura[Cobertura] ),
    BLANK (),
    "Selecione uma cobertura: IGR médico e odontológico têm escalas ~50× diferentes"
)

Texto Período =
VAR _Ini = CALCULATE ( MIN ( D_Tempo[DataMes] ), F_IGR )
VAR _Fim = CALCULATE ( MAX ( D_Tempo[DataMes] ), F_IGR )
RETURN "IGR de " & FORMAT ( _Ini, "mmm/yyyy" ) & " a " & FORMAT ( _Fim, "mmm/yyyy" )

Cor IGR vs Mercado =
IF ( [IGR] > [IGR Mercado], "#f47230", "#257de0" )

Rótulo Fonte =
"Fonte: ANS — Dados Abertos (CADOP, IGR metodologia 2023, TR). Atualização: " &
FORMAT ( MAX ( D_Operadora[DtCargaDW] ), "dd/mm/yyyy" )
```
- `Cor IGR vs Mercado`: em barras, Formatação condicional → Cor → *Valor do campo*.
- `Rótulo Fonte`: num cartão de texto pequeno no rodapé de todas as páginas.
