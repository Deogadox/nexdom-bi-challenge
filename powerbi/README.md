# Power BI — conexão e modelo semântico

O dashboard é montado manualmente no Power BI Desktop, consumindo **somente o DW** do SQL Server.
Arquivos desta pasta: [`dax_measures.md`](dax_measures.md) (medidas), [`dashboard_layout.md`](dashboard_layout.md)
(páginas e gráficos) e [`tema_nexdom.json`](tema_nexdom.json) (tema de cores).

## 1. Conexão
**Obter dados → SQL Server** · Servidor `localhost` · Banco `ANS_BI` · Modo **Importar** (cerca de 200 mil linhas de
fato; Import dá DAX completo e desempenho, e a atualização é mensal).

Tabelas a importar (todas do schema `DW`):

| Tabela | Papel | Grão |
|---|---|---|
| `DimOperadora` | dimensão | registro ANS |
| `DimSegmento` | dimensão | modalidade (com `Segmento` e `GrupoAssistencial`) |
| `DimTempo` | dimensão | mês (`SkTempo` = AAAAMM) |
| `DimCobertura`, `DimNatureza`, `DimPorte` | dimensões | domínio |
| `FatoIGR` | fato | operadora × cobertura × mês |
| `FatoTR` | fato | operadora × natureza × mês |
| `AnaliseR2Operadora` | resultado estatístico | operadora × cobertura (IGR 12 meses atuais) |
| `AnaliseR1Operadora` | resultado estatístico | operadora (IGR × TR, mai/2018–abr/2019) |

No Power Query, **desmarque** (Ocultar no modo de relatório) as colunas técnicas: `IdExecucaoDW`, `DtCargaDW`,
`DtPublicacao`, `IGRPublicado`, `VlTRPublicado`, `FlIGRDivergente`.

## 2. Relacionamentos (todos 1:*, filtro em direção única)

```
DimSegmento[SkSegmento]   1 ─── * DimOperadora[SkSegmento]
DimOperadora[SkOperadora] 1 ─── * FatoIGR, FatoTR, AnaliseR2Operadora, AnaliseR1Operadora
DimTempo[SkTempo]         1 ─── * FatoIGR[SkTempo], FatoTR[SkTempo]
DimCobertura[SkCobertura] 1 ─── * FatoIGR, AnaliseR2Operadora, AnaliseR1Operadora
DimNatureza[SkNatureza]   1 ─── * FatoTR
DimPorte[SkPorte]         1 ─── * FatoIGR
```

- **`FatoIGR` e `FatoTR` não se relacionam entre si**: IGR quebra por cobertura e TR por natureza. Um relacionamento
  direto seria muitos-para-muitos e multiplicaria linhas. A comparação passa pelas dimensões compartilhadas.
- `FatoIGR[SkTempoBeneficiario]` **não** recebe relacionamento (papel secundário, só para auditoria).
- Não marque `DimTempo` como tabela de datas: o grão é mensal. A comparação com o ano anterior está resolvida no DAX
  pelo `SkTempo` (veja `dax_measures.md`).

## 3. Ajustes de modelagem
- `DimTempo[AnoMes]` → *Classificar por coluna* `SkTempo`; `DimTempo[NomeMes]` → classificar por `Mes`.
- `DimPorte[Porte]` → classificar por `Ordem`.
- Hierarquia `Ano > Mês` em `DimTempo`; hierarquia `Grupo assistencial > Segmento` em `DimSegmento`.
- Formato de `IGR`: decimal com 2 casas. Formato de `TR`: percentual com 1 casa.
- Ocultar as chaves (`Sk*`) no modo de relatório.

## 4. Regras que o relatório precisa respeitar
1. **IGR médico e odontológico nunca no mesmo eixo ou ranking** (escalas cerca de 50 vezes diferentes): use a
   cobertura como filtro de página ou segmentação obrigatória.
2. **Recortes temporais:** o IGR vigente vai de 2021-05 a 2026-10; a TR, de 2015-01 a 2019-10; IGR × TR só em
   2015-01 → 2019-04 (`DimTempo[FlJanelaComumIGRTR]`). Não compare o nível da série congelada com o da vigente
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
| Linhas de `AnaliseR2Operadora` com `Elegivel` = verdadeiro e cobertura médica | contagem | **511** |
| Linhas de `AnaliseR1Operadora` com `Quadrante` "Crítico…" | contagem | **52** (49 médico-hospitalares + 3 odontológicas) |

O "IGR do mercado" de 52,33 em `docs/resultados_analises.md` considera **só as elegíveis**, pois é a referência do
funil. No dashboard, o card principal usa todas as operadoras (53,86) e o rótulo deve deixar isso claro.
