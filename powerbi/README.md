# Power BI — conexão e modelo semântico

O dashboard é montado manualmente no Power BI Desktop, consumindo **somente o DW** do SQL Server.
Arquivos desta pasta: [`dax_measures.md`](dax_measures.md) (medidas), [`dashboard_layout.md`](dashboard_layout.md)
(páginas e gráficos) e [`tema_nexdom.json`](tema_nexdom.json) (tema de cores).

## 1. Conexão
**Obter dados → SQL Server** · Servidor `localhost` · Banco `ANS_BI` · Modo **Importar** (cerca de 200 mil linhas de
fato; Import dá DAX completo e desempenho, e a atualização é mensal).

Cada tabela entra por uma **consulta SQL** (*Opções avançadas → Instrução SQL*) que traz só as colunas usadas pelo
modelo. Depois, **renomeie a consulta** com o nome da coluna "Consulta no Power BI": as medidas DAX usam esses nomes.

| Consulta no Power BI | Tabela no SQL Server | Papel | Grão |
|---|---|---|---|
| `D_Operadora` | `DW.DimOperadora` | dimensão | registro ANS |
| `D_Segmento` | `DW.DimSegmento` | dimensão | modalidade (com `Segmento` e `GrupoAssistencial`) |
| `D_Tempo` | `DW.DimTempo` | dimensão | mês (`SkTempo` = AAAAMM) |
| `D_Cobertura` · `D_Natureza` · `D_Porte` | `DW.DimCobertura` · `DW.DimNatureza` · `DW.DimPorte` | dimensões | domínio |
| `F_IGR` | `DW.FatoIGR` | fato | operadora × cobertura × mês |
| `F_TR` | `DW.FatoTR` | fato | operadora × natureza × mês |
| `Anl_R2Operadora` | `DW.AnaliseR2Operadora` | resultado estatístico | operadora × cobertura (IGR 12 meses atuais) |
| `Anl_R1Operadora` | `DW.AnaliseR1Operadora` | resultado estatístico | operadora (IGR × TR, mai/2018–abr/2019) |
| `Glossario` | `DW.Glossario` | documentação (sem relacionamentos) | termo (41 medidas + 12 conceitos) |

Convenção: `D_` dimensão · `F_` fato · `Anl_` resultado estatístico. No banco, os nomes seguem o padrão do DW
(`Dim`, `Fato`, `Analise`).

<details><summary><b>Consultas SQL (uma por tabela)</b></summary>

```sql
-- D_Operadora
SELECT SkOperadora, RegistroANS, CNPJ, RazaoSocial, NomeFantasia, NomeExibicao, SkSegmento,
       UF, Cidade, Situacao, DtRegistroANS, DtDescredenciamento, MotivoDescredenciamento, DtCargaDW
FROM DW.DimOperadora;

-- D_Segmento
SELECT SkSegmento, Modalidade, Segmento, GrupoAssistencial, FlModalidadeLegada FROM DW.DimSegmento;

-- D_Tempo
SELECT SkTempo, DataMes, Ano, Mes, NomeMes, AnoMes, Trimestre, Semestre,
       FlIGRDisponivel, FlTRDisponivel, FlJanelaComumIGRTR, SerieIGR
FROM DW.DimTempo;

-- D_Cobertura · D_Natureza · D_Porte
SELECT SkCobertura, Cobertura FROM DW.DimCobertura;
SELECT SkNatureza, Natureza, FlTotal FROM DW.DimNatureza;
SELECT SkPorte, Porte, Ordem, FaixaBeneficiarios FROM DW.DimPorte;

-- F_IGR
SELECT SkOperadora, SkTempo, SkCobertura, SkPorte, QtdReclamacoes, QtdBeneficiarios FROM DW.FatoIGR;

-- F_TR
SELECT SkOperadora, SkTempo, SkNatureza, Numerador, Denominador FROM DW.FatoTR;

-- Anl_R2Operadora
SELECT SkOperadora, SkCobertura, JanelaInicio, JanelaFim, Reclamacoes, BenefSoma, BenefMedio, Meses,
       IGR, PorteUltimoMes, Elegivel, Esperado, ZFunil, LimInfIGR, LimSupIGR, Funil,
       IQRSegmento, ZRobSegmento, OutlierConsistente
FROM DW.AnaliseR2Operadora;

-- Anl_R1Operadora
SELECT SkOperadora, SkCobertura, GrupoAssistencial, JanelaInicio, JanelaFim, Reclamacoes, BenefMedio,
       IGR, Demandas, Resolvidas, TRGeral, TRAssistencial, TRNaoAssistencial, Elegivel,
       ScoreIGR, ScoreTR, IndiceCombinado, Quadrante
FROM DW.AnaliseR1Operadora;

-- Glossario (tabela desconectada: não recebe relacionamentos)
SELECT Ordem, Tipo, Termo, Pasta, Definicao, Calculo, Unidade, Sentido, Observacao, ExpressaoDAX
FROM DW.Glossario;
```
</details>

As consultas já deixam de fora as colunas técnicas e de auditoria (`IdExecucaoDW`, `IGRPublicado`, `VlTRPublicado`,
`FlIGRDivergente`, `SkTempoBeneficiario`, `DtPublicacao`). No Power Query, confira:
- `Fl*`, `Elegivel` e `OutlierConsistente` com o tipo **Verdadeiro/Falso**, e `DataMes` com o tipo **Data**;
- as contagens: `F_IGR` 130.136 · `F_TR` 63.366 · `D_Operadora` 4.187 · `Anl_R2Operadora` 998 · `Anl_R1Operadora` 742 · `Glossario` 53.

**Criação das medidas** (com a tabela `Medidas` e os parâmetros já criados), duas opções geradas do mesmo catálogo:
- **Uma a uma (recomendado):** [`medidas_uma_a_uma.md`](medidas_uma_a_uma.md), com as 41 medidas na ordem de dependência,
  cada uma com código, pasta, formato e descrição.
- **Todas de uma vez:** [`medidas.dax`](medidas.dax) na Exibição de consulta DAX → link **Atualizar modelo** acima de `DEFINE`.

## 2. Relacionamentos (todos 1:*, filtro em direção única)

```
D_Segmento[SkSegmento]   1 ─── * D_Operadora[SkSegmento]
D_Operadora[SkOperadora] 1 ─── * F_IGR, F_TR, Anl_R2Operadora, Anl_R1Operadora
D_Tempo[SkTempo]         1 ─── * F_IGR[SkTempo], F_TR[SkTempo]
D_Cobertura[SkCobertura] 1 ─── * F_IGR, Anl_R2Operadora, Anl_R1Operadora
D_Natureza[SkNatureza]   1 ─── * F_TR
D_Porte[SkPorte]         1 ─── * F_IGR
```

- **`F_IGR` e `F_TR` não se relacionam entre si**: IGR quebra por cobertura e TR por natureza. Um relacionamento
  direto seria muitos-para-muitos e multiplicaria linhas. A comparação passa pelas dimensões compartilhadas.
- **`D_Operadora` → `Anl_R1Operadora`:** como `SkOperadora` é única nas duas tabelas, o Power BI cria a relação como
  **1:1 bidirecional**. Isso cria ambiguidade e desativa (tracejada) a ligação `D_Cobertura` → `Anl_R1Operadora`.
  **Corrija:** cardinalidade *Muitos para um* (`Anl_R1Operadora` no lado "muitos"), filtro *Único*, e depois ative a
  ligação com `D_Cobertura`. Todas as linhas do modelo devem ficar contínuas, com 1 de um lado e * do outro.
- Não marque `D_Tempo` como tabela de datas: o grão é mensal. A comparação com o ano anterior está resolvida no DAX
  pelo `SkTempo` (veja `dax_measures.md`).

## 3. Ajustes de modelagem
- `D_Tempo[AnoMes]` → *Classificar por coluna* `SkTempo`; `D_Tempo[NomeMes]` → classificar por `Mes`.
- `D_Porte[Porte]` → classificar por `Ordem`.
- Hierarquia `Ano > Mês` em `D_Tempo`; hierarquia `Grupo assistencial > Segmento` em `D_Segmento`.
- Formato de `IGR`: decimal com 2 casas. Formato de `TR`: percentual com 1 casa.
- Ocultar as chaves (`Sk*`) no modo de relatório.

## 4. Regras que o relatório precisa respeitar
1. **IGR médico e odontológico nunca no mesmo eixo ou ranking** (escalas cerca de 50 vezes diferentes): use a
   cobertura como filtro de página ou segmentação obrigatória.
2. **Recortes temporais:** o IGR vigente vai de 2021-05 a 2026-10; a TR, de 2015-01 a 2019-10; IGR × TR só em
   2015-01 → 2019-04 (`D_Tempo[FlJanelaComumIGRTR]`). Não compare o nível da série congelada com o da vigente
   (houve quebra metodológica).
3. Taxas sempre como **soma/soma** (as medidas já fazem isso); nunca a média de `IGRCalculado` ou de `IGR`.

## 5. Validação após montar
Valores de referência calculados a partir do DW (todas as operadoras, sem filtro de elegibilidade).
Se não baterem, confira relacionamentos e filtros.

| Filtros | Medida | Esperado |
|---|---|---|
| `SkTempo` 202511–202610, cobertura *Assistência médica* | `[IGR]` | **53,86** (341.831 reclamações) |
| idem, segmento *Seguradora Especializada em Saúde* | `[IGR]` | **74,25** |
| idem, segmento *Medicina de Grupo* | `[IGR]` | **60,82** |
| idem, segmento *Cooperativa Médica* | `[IGR]` | **39,90** |
| `SkTempo` 202501–202510, *Assistência médica* | `[IGR]` | **50,62** |
| Linhas de `Anl_R2Operadora` com `Elegivel` = verdadeiro e cobertura médica | contagem | **511** |
| Linhas de `Anl_R1Operadora` com `Quadrante` "Crítico…" | contagem | **52** (49 médico-hospitalares + 3 odontológicas) |

O "IGR do mercado" de 52,33 em `docs/resultados_analises.md` considera **só as elegíveis**, pois é a referência do
funil. No dashboard, o card principal usa todas as operadoras (53,86) e o rótulo deve deixar isso claro.
