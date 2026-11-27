# Medidas — criação uma a uma

<!-- GERADO por src/semantic/gerar.py a partir de src/semantic/catalogo.py — não edite à mão. -->

Crie na ordem abaixo: cada medida só usa as anteriores. Para cada uma:
1. Painel **Dados** → botão direito em `Medidas` → **Nova medida**.
2. Cole o código na barra de fórmulas e pressione **Enter**.
3. **Ferramentas de medida → Formato**: use o formato indicado (personalizado quando for o caso).
4. **Exibição de modelo → Propriedades**: preencha **Pasta de exibição** e **Descrição**.

Antes de começar: tabela `Medidas` e parâmetros `Peso IGR` (0 a 1, passo 0,05, padrão 0,5) e
`Benef Mínimo` (0 a 100.000, passo 1.000, padrão 5.000). Explicações detalhadas: [`dax_measures.md`](dax_measures.md).

## Pasta `0 Parâmetros`

### 1. Peso IGR Valor

- **Pasta:** `0 Parâmetros` · **Formato:** `0.00` · **Leitura:** Neutro
- **Descrição:** Peso do IGR no Índice Combinado, escolhido pelo usuário no parâmetro 'Peso IGR'. O peso da TR é 1 − este valor.

```DAX
Peso IGR Valor =
SELECTEDVALUE ( 'Peso IGR'[Peso IGR], 0.5 )
```

### 2. Benef Mínimo Valor

- **Pasta:** `0 Parâmetros` · **Formato:** `#,##0` · **Leitura:** Neutro
- **Descrição:** Volume mínimo de beneficiários médios para uma operadora entrar em rankings e medianas.

```DAX
Benef Mínimo Valor =
SELECTEDVALUE ( 'Benef Mínimo'[Benef Mínimo], 5000 )
```

## Pasta `1 IGR`

### 3. Reclamações

- **Pasta:** `1 IGR` · **Formato:** `#,##0` · **Leitura:** Maior = pior
- **Descrição:** Quantidade de reclamações de beneficiários registradas na ANS (NIP) no período e recorte selecionados.

```DAX
Reclamações =
SUM ( F_IGR[QtdReclamacoes] )
```

### 4. Beneficiários (soma mensal)

- **Pasta:** `1 IGR` · **Formato:** `#,##0` · **Leitura:** Neutro
- **Descrição:** Soma dos beneficiários de cada mês do período. Denominador do IGR.

```DAX
Beneficiários (soma mensal) =
SUM ( F_IGR[QtdBeneficiarios] )
```

### 5. Meses com IGR

- **Pasta:** `1 IGR` · **Formato:** `#,##0` · **Leitura:** Neutro
- **Descrição:** Quantidade de meses com dado de IGR no contexto (operadora, segmento, período).

```DAX
Meses com IGR =
DISTINCTCOUNT ( F_IGR[SkTempo] )
```

### 6. Beneficiários Médios

- **Pasta:** `1 IGR` · **Formato:** `#,##0` · **Leitura:** Neutro
- **Descrição:** Média mensal de beneficiários no período. Medida de porte.

```DAX
Beneficiários Médios =
DIVIDE ( [Beneficiários (soma mensal)], [Meses com IGR] )
```

### 7. IGR

- **Pasta:** `1 IGR` · **Formato:** `#,##0.00` · **Leitura:** Maior = pior
- **Descrição:** Índice Geral de Reclamações: reclamações para cada 100 mil beneficiários. Indicador oficial da ANS (metodologia 2023).

```DAX
IGR =
DIVIDE ( [Reclamações], [Beneficiários (soma mensal)] ) * 100000
```

### 8. IGR Mercado

- **Pasta:** `1 IGR` · **Formato:** `#,##0.00` · **Leitura:** Maior = pior
- **Descrição:** IGR de todo o mercado no mesmo período e cobertura. Referência para comparar uma operadora ou um segmento.

```DAX
IGR Mercado =
CALCULATE ( [IGR], REMOVEFILTERS ( D_Operadora ), REMOVEFILTERS ( D_Segmento ), REMOVEFILTERS ( D_Porte ) )
```

### 9. Operadoras com IGR

- **Pasta:** `1 IGR` · **Formato:** `#,##0` · **Leitura:** Neutro
- **Descrição:** Quantidade de operadoras com beneficiários e IGR no período.

```DAX
Operadoras com IGR =
CALCULATE ( DISTINCTCOUNT ( F_IGR[SkOperadora] ), F_IGR[QtdBeneficiarios] > 0 )
```

## Pasta `2 TR`

### 10. Demandas NIP

- **Pasta:** `2 TR` · **Formato:** `#,##0` · **Leitura:** Neutro
- **Descrição:** Demandas de reclamação (NIP) classificadas: denominador da Taxa de Resolutividade.

```DAX
Demandas NIP =
VAR _ApenasTotal = NOT ISFILTERED ( D_Natureza[Natureza] )
RETURN
    IF (
        _ApenasTotal,
        CALCULATE ( SUM ( F_TR[Denominador] ), D_Natureza[FlTotal] = TRUE () ),
        CALCULATE ( SUM ( F_TR[Denominador] ), KEEPFILTERS ( D_Natureza[FlTotal] = FALSE () ) )
    )
```

### 11. Demandas Resolvidas

- **Pasta:** `2 TR` · **Formato:** `#,##0` · **Leitura:** Maior = melhor
- **Descrição:** Demandas resolvidas por mediação, sem abertura de processo sancionador: numerador da TR.

```DAX
Demandas Resolvidas =
VAR _ApenasTotal = NOT ISFILTERED ( D_Natureza[Natureza] )
RETURN
    IF (
        _ApenasTotal,
        CALCULATE ( SUM ( F_TR[Numerador] ), D_Natureza[FlTotal] = TRUE () ),
        CALCULATE ( SUM ( F_TR[Numerador] ), KEEPFILTERS ( D_Natureza[FlTotal] = FALSE () ) )
    )
```

### 12. TR

- **Pasta:** `2 TR` · **Formato:** `0.0%` · **Leitura:** Maior = melhor
- **Descrição:** Taxa de Resolutividade: percentual das reclamações resolvidas na mediação da ANS. Indicador oficial.

```DAX
TR =
DIVIDE ( [Demandas Resolvidas], [Demandas NIP] )
```

## Pasta `3 Tempo`

### 13. Meses no Período

- **Pasta:** `3 Tempo` · **Formato:** `#,##0` · **Leitura:** Neutro
- **Descrição:** Quantidade de meses com dado no período selecionado, independentemente de operadora, segmento ou porte.

```DAX
Meses no Período =
CALCULATE (
    DISTINCTCOUNT ( F_IGR[SkTempo] ),
    REMOVEFILTERS ( D_Operadora ), REMOVEFILTERS ( D_Segmento ), REMOVEFILTERS ( D_Porte )
)
```

### 14. IGR Ano Anterior

- **Pasta:** `3 Tempo` · **Formato:** `#,##0.00` · **Leitura:** Maior = pior
- **Descrição:** IGR dos mesmos meses do ano anterior.

```DAX
IGR Ano Anterior =
VAR _MesesAnt =
    SELECTCOLUMNS ( VALUES ( D_Tempo[SkTempo] ), "SkTempo", D_Tempo[SkTempo] - 100 )
RETURN
    CALCULATE ( [IGR], REMOVEFILTERS ( D_Tempo ), TREATAS ( _MesesAnt, D_Tempo[SkTempo] ) )
```

### 15. Var % IGR a.a.

- **Pasta:** `3 Tempo` · **Formato:** `+0.0%;-0.0%;0.0%` · **Leitura:** Positivo = piora
- **Descrição:** Variação percentual do IGR em relação aos mesmos meses do ano anterior.

```DAX
Var % IGR a.a. =
VAR _MesesAnt =
    SELECTCOLUMNS ( VALUES ( D_Tempo[SkTempo] ), "SkTempo", D_Tempo[SkTempo] - 100 )
VAR _QtdAtual = [Meses no Período]
VAR _QtdAnt =
    CALCULATE ( [Meses no Período], REMOVEFILTERS ( D_Tempo ), TREATAS ( _MesesAnt, D_Tempo[SkTempo] ) )
VAR _Ant = [IGR Ano Anterior]
RETURN
    IF ( _QtdAtual = _QtdAnt && NOT ISBLANK ( _Ant ), DIVIDE ( [IGR] - _Ant, _Ant ) )
```

### 16. TR Ano Anterior

- **Pasta:** `3 Tempo` · **Formato:** `0.0%` · **Leitura:** Maior = melhor
- **Descrição:** TR dos mesmos meses do ano anterior.

```DAX
TR Ano Anterior =
VAR _MesesAnt =
    SELECTCOLUMNS ( VALUES ( D_Tempo[SkTempo] ), "SkTempo", D_Tempo[SkTempo] - 100 )
RETURN
    CALCULATE ( [TR], REMOVEFILTERS ( D_Tempo ), TREATAS ( _MesesAnt, D_Tempo[SkTempo] ) )
```

### 17. Var TR a.a. (p.p.)

- **Pasta:** `3 Tempo` · **Formato:** `+0.0;-0.0;0.0` · **Leitura:** Positivo = melhora
- **Descrição:** Diferença da TR em relação aos mesmos meses do ano anterior, em pontos percentuais.

```DAX
Var TR a.a. (p.p.) =
VAR _Ant = [TR Ano Anterior]
RETURN IF ( NOT ISBLANK ( _Ant ) && NOT ISBLANK ( [TR] ), ( [TR] - _Ant ) * 100 )
```

## Pasta `4 Ranking`

### 18. Operadora Elegível

- **Pasta:** `4 Ranking` · **Formato:** `0` · **Leitura:** Neutro
- **Descrição:** Indica se a operadora entra em rankings e medianas no período selecionado.

```DAX
Operadora Elegível =
IF (
    [Meses com IGR] = [Meses no Período] && [Beneficiários Médios] >= [Benef Mínimo Valor],
    1, 0
)
```

### 19. Operadoras Elegíveis

- **Pasta:** `4 Ranking` · **Formato:** `#,##0` · **Leitura:** Neutro
- **Descrição:** Quantidade de operadoras elegíveis no contexto.

```DAX
Operadoras Elegíveis =
COUNTROWS ( FILTER ( VALUES ( D_Operadora[SkOperadora] ), [Operadora Elegível] = 1 ) )
```

### 20. IGR Mediano (operadoras elegíveis)

- **Pasta:** `4 Ranking` · **Formato:** `#,##0.00` · **Leitura:** Maior = pior
- **Descrição:** IGR da operadora típica: mediana dos IGRs das operadoras elegíveis.

```DAX
IGR Mediano (operadoras elegíveis) =
MEDIANX ( FILTER ( VALUES ( D_Operadora[SkOperadora] ), [Operadora Elegível] = 1 ), [IGR] )
```

### 21. Ranking IGR (1 = pior)

- **Pasta:** `4 Ranking` · **Formato:** `0` · **Leitura:** 1 = maior IGR
- **Descrição:** Posição da operadora entre as elegíveis, do maior para o menor IGR.

```DAX
Ranking IGR (1 = pior) =
IF (
    HASONEVALUE ( D_Operadora[NomeExibicao] ) && [Operadora Elegível] = 1,
    CALCULATE (
        RANKX (
            FILTER ( ALLSELECTED ( D_Operadora[NomeExibicao] ), [Operadora Elegível] = 1 ),
            [IGR], , DESC, DENSE
        ),
        ALLSELECTED ( D_Segmento )
    )
)
```

### 22. Ranking IGR (1 = melhor)

- **Pasta:** `4 Ranking` · **Formato:** `0` · **Leitura:** 1 = menor IGR
- **Descrição:** Posição da operadora entre as elegíveis, do menor para o maior IGR.

```DAX
Ranking IGR (1 = melhor) =
IF (
    HASONEVALUE ( D_Operadora[NomeExibicao] ) && [Operadora Elegível] = 1,
    CALCULATE (
        RANKX (
            FILTER ( ALLSELECTED ( D_Operadora[NomeExibicao] ), [Operadora Elegível] = 1 ),
            [IGR], , ASC, DENSE
        ),
        ALLSELECTED ( D_Segmento )
    )
)
```

### 23. IGR do Segmento

- **Pasta:** `4 Ranking` · **Formato:** `#,##0.00` · **Leitura:** Maior = pior
- **Descrição:** IGR agregado do segmento (modalidade) a que a operadora pertence.

```DAX
IGR do Segmento =
VAR _Seg = SELECTEDVALUE ( D_Operadora[SkSegmento] )
RETURN
    CALCULATE ( [IGR], REMOVEFILTERS ( D_Operadora ), D_Operadora[SkSegmento] = _Seg )
```

### 24. IGR Relativo ao Segmento

- **Pasta:** `4 Ranking` · **Formato:** `0.00x` · **Leitura:** > 1 = pior que o segmento
- **Descrição:** Quantas vezes o IGR da operadora é maior (ou menor) que o do próprio segmento.

```DAX
IGR Relativo ao Segmento =
DIVIDE ( [IGR], [IGR do Segmento] )
```

### 25. Ranking no Segmento (1 = pior)

- **Pasta:** `4 Ranking` · **Formato:** `0` · **Leitura:** 1 = maior IGR do segmento
- **Descrição:** Posição da operadora dentro do próprio segmento, do maior para o menor IGR.

```DAX
Ranking no Segmento (1 = pior) =
VAR _Seg = SELECTEDVALUE ( D_Operadora[SkSegmento] )
RETURN
    IF (
        HASONEVALUE ( D_Operadora[NomeExibicao] ) && [Operadora Elegível] = 1,
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
```

### 26. Pior Operadora (IGR)

- **Pasta:** `4 Ranking` · **Formato:** `Texto` · **Leitura:** —
- **Descrição:** Nome da operadora elegível com o maior IGR no contexto.

```DAX
Pior Operadora (IGR) =
CONCATENATEX (
    TOPN ( 1, FILTER ( VALUES ( D_Operadora[NomeExibicao] ), [Operadora Elegível] = 1 ), [IGR], DESC ),
    D_Operadora[NomeExibicao], ", "
)
```

### 27. Melhor Operadora (IGR)

- **Pasta:** `4 Ranking` · **Formato:** `Texto` · **Leitura:** —
- **Descrição:** Nome da operadora elegível com o menor IGR no contexto.

```DAX
Melhor Operadora (IGR) =
CONCATENATEX (
    TOPN ( 1, FILTER ( VALUES ( D_Operadora[NomeExibicao] ), [Operadora Elegível] = 1 ),
           [IGR], ASC, [Beneficiários Médios], DESC ),
    D_Operadora[NomeExibicao], ", "
)
```

## Pasta `5 Concentração`

### 28. % das Reclamações

- **Pasta:** `5 Concentração` · **Formato:** `0.0%` · **Leitura:** Neutro
- **Descrição:** Participação da operadora (ou do segmento) no total de reclamações selecionado.

```DAX
% das Reclamações =
DIVIDE (
    [Reclamações],
    CALCULATE ( [Reclamações], ALLSELECTED ( D_Operadora ), ALLSELECTED ( D_Segmento ) )
)
```

### 29. % Acumulado das Reclamações

- **Pasta:** `5 Concentração` · **Formato:** `0.0%` · **Leitura:** Neutro
- **Descrição:** Percentual acumulado das reclamações, da operadora com mais reclamações para a com menos (curva de Pareto).

```DAX
% Acumulado das Reclamações =
VAR _Atual = [Reclamações]
VAR _Tab =
    CALCULATETABLE (
        ADDCOLUMNS ( ALLSELECTED ( D_Operadora[NomeExibicao] ), "@Rec", [Reclamações] ),
        ALLSELECTED ( D_Segmento )
    )
RETURN
    DIVIDE ( SUMX ( FILTER ( _Tab, [@Rec] >= _Atual ), [@Rec] ), SUMX ( _Tab, [@Rec] ) )
```

## Pasta `6 Estatística`

### 30. Operadoras Elegíveis (R2)

- **Pasta:** `6 Estatística` · **Formato:** `#,##0` · **Leitura:** Neutro
- **Descrição:** Operadoras elegíveis no recorte atual (R2) da análise estatística.

```DAX
Operadoras Elegíveis (R2) =
CALCULATE ( COUNTROWS ( Anl_R2Operadora ), Anl_R2Operadora[Elegivel] = TRUE () )
```

### 31. Outliers Críticos (atual)

- **Pasta:** `6 Estatística` · **Formato:** `#,##0` · **Leitura:** Maior = pior
- **Descrição:** Operadoras com IGR estatisticamente acima do esperado e discrepantes no próprio segmento (recorte atual).

```DAX
Outliers Críticos (atual) =
CALCULATE (
    COUNTROWS ( Anl_R2Operadora ),
    Anl_R2Operadora[OutlierConsistente] = TRUE (),
    Anl_R2Operadora[Funil] = "Acima (pior)"
)
```

### 32. % Outliers Críticos

- **Pasta:** `6 Estatística` · **Formato:** `0.0%` · **Leitura:** Maior = pior
- **Descrição:** Percentual das operadoras elegíveis classificadas como outlier crítico.

```DAX
% Outliers Críticos =
DIVIDE ( [Outliers Críticos (atual)], [Operadoras Elegíveis (R2)] )
```

### 33. Excesso de Reclamações (atual)

- **Pasta:** `6 Estatística` · **Formato:** `#,##0` · **Leitura:** Maior = pior
- **Descrição:** Reclamações acima (ou abaixo, se negativo) do que seria esperado se a operadora tivesse o IGR do mercado.

```DAX
Excesso de Reclamações (atual) =
CALCULATE (
    SUM ( Anl_R2Operadora[Reclamacoes] ) - SUM ( Anl_R2Operadora[Esperado] ),
    Anl_R2Operadora[Elegivel] = TRUE ()
)
```

### 34. Índice Combinado

- **Pasta:** `6 Estatística` · **Formato:** `0.0` · **Leitura:** Maior = melhor
- **Descrição:** Indicador do projeto que combina IGR e TR numa nota de 0 a 100 (recorte 2018–19).

```DAX
Índice Combinado =
VAR _W = [Peso IGR Valor]
RETURN
    AVERAGEX (
        FILTER ( Anl_R1Operadora, Anl_R1Operadora[Elegivel] = TRUE () ),
        _W * Anl_R1Operadora[ScoreIGR] + ( 1 - _W ) * Anl_R1Operadora[ScoreTR]
    )
```

### 35. Ranking Índice (1 = melhor)

- **Pasta:** `6 Estatística` · **Formato:** `0` · **Leitura:** 1 = melhor
- **Descrição:** Posição da operadora pelo Índice Combinado.

```DAX
Ranking Índice (1 = melhor) =
IF (
    HASONEVALUE ( D_Operadora[NomeExibicao] ) && NOT ISBLANK ( [Índice Combinado] ),
    CALCULATE (
        RANKX (
            FILTER ( ALLSELECTED ( D_Operadora[NomeExibicao] ), NOT ISBLANK ( [Índice Combinado] ) ),
            [Índice Combinado], , DESC, DENSE
        ),
        ALLSELECTED ( D_Segmento )
    )
)
```

### 36. Operadoras Críticas (IGR alto e TR baixa)

- **Pasta:** `6 Estatística` · **Formato:** `#,##0` · **Leitura:** Maior = pior
- **Descrição:** Operadoras com IGR acima da mediana e TR abaixo da mediana do grupo (recorte 2018–19).

```DAX
Operadoras Críticas (IGR alto e TR baixa) =
CALCULATE (
    COUNTROWS ( Anl_R1Operadora ),
    Anl_R1Operadora[Quadrante] = "Crítico: IGR alto e TR baixa"
)
```

### 37. % Operadoras Críticas

- **Pasta:** `6 Estatística` · **Formato:** `0.0%` · **Leitura:** Maior = pior
- **Descrição:** Percentual das operadoras elegíveis do recorte 2018–19 no quadrante crítico.

```DAX
% Operadoras Críticas =
DIVIDE (
    [Operadoras Críticas (IGR alto e TR baixa)],
    CALCULATE ( COUNTROWS ( Anl_R1Operadora ), Anl_R1Operadora[Elegivel] = TRUE () )
)
```

## Pasta `7 UX`

### 38. Aviso Cobertura

- **Pasta:** `7 UX` · **Formato:** `Texto` · **Leitura:** —
- **Descrição:** Mensagem exibida quando mais de uma cobertura está selecionada.

```DAX
Aviso Cobertura =
IF (
    HASONEVALUE ( D_Cobertura[Cobertura] ),
    BLANK (),
    "Selecione uma cobertura: IGR médico e odontológico têm escalas ~50× diferentes"
)
```

### 39. Texto Período

- **Pasta:** `7 UX` · **Formato:** `Texto` · **Leitura:** —
- **Descrição:** Período do IGR efetivamente exibido, para títulos dinâmicos.

```DAX
Texto Período =
VAR _Ini = CALCULATE ( MIN ( D_Tempo[DataMes] ), F_IGR )
VAR _Fim = CALCULATE ( MAX ( D_Tempo[DataMes] ), F_IGR )
RETURN "IGR de " & FORMAT ( _Ini, "mmm/yyyy" ) & " a " & FORMAT ( _Fim, "mmm/yyyy" )
```

### 40. Cor IGR vs Mercado

- **Pasta:** `7 UX` · **Formato:** `Texto` · **Leitura:** —
- **Descrição:** Cor para formatação condicional: laranja se o IGR está acima do mercado, azul se está abaixo.

```DAX
Cor IGR vs Mercado =
IF ( [IGR] > [IGR Mercado], "#f47230", "#257de0" )
```

### 41. Rótulo Fonte

- **Pasta:** `7 UX` · **Formato:** `Texto` · **Leitura:** —
- **Descrição:** Texto de rodapé com as fontes e a data da última carga do DW.

```DAX
Rótulo Fonte =
"Fonte: ANS — Dados Abertos (CADOP, IGR metodologia 2023, TR). Atualização: " &
FORMAT ( MAX ( D_Operadora[DtCargaDW] ), "dd/mm/yyyy" )
```
