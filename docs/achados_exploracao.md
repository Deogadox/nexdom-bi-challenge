# Achados da exploração das bases completas (Fase 2)

Execução: 25/11/2026, `run_local.ps1` (download + `profile_raw.py`), arquivos com DT_ATUALIZACAO 2026-11-09.
Detalhe completo gerado em `docs/profiling_raw.md` (local).

## Volumes

| Base | Linhas | Colunas | Registros ANS distintos | Grão confirmado |
|---|---|---|---|---|
| CADOP ativas | 1.101 | 20 | 1.101 | registro ANS (único) |
| CADOP canceladas | 3.085 | 22 (+ data e motivo do descredenciamento) | 3.085 | registro ANS (único) |
| IGR | 130.155 | 10 | 1.417 | operadora × cobertura × competência (**38 duplicidades**, ver A3) |
| TR | 63.366 | 8 | 1.210 | operadora × natureza × competência (único) |

## A1 — Períodos não se sobrepõem integralmente (achado crítico)

| Base | Cobertura temporal |
|---|---|
| IGR | 2015-01 → 2019-04 (série **congelada**, `DT_ATUALIZACAO` vazio) **+** 2021-05 → 2026-10 (série viva). Lacuna de 24 meses: 2019-05 → 2021-04 |
| TR | 2015-01 → 2019-10, sem meses faltantes. **Não há TR após 2019-10** no arquivo oficial |

- Janela comum IGR × TR: **2015-01 → 2019-04 (52 meses)**.
- Contexto oficial: a ANS passou a usar a Taxa de Intermediação Resolvida (TIR) no lugar da TR em 2025 (painel lançado em 05/03/2025).
- Consequência: qualquer análise que combine IGR e TR só é válida na janela 2015–2019; o IGR atual (2021–2026) não tem TR correspondente.

## A2 — Natureza da TR tem três valores
`Assistencial` (22.340), `Não Assistencial` (14.964) e **`Geral`** (26.062). Em 100% dos 11.242 casos com as três,
`Geral = Assistencial + Não Assistencial` (numerador e denominador). `Geral` é um total pré-agregado → não pode ser
somado com as demais no fato (dupla contagem). Regra: o fato guarda as três naturezas; o DAX usa `Geral` para o total.

## A3 — Duplicidades no IGR
38 linhas, todas na competência 2019-04: mesmo registro/cobertura/competência, **mesmas métricas**, razão social
diferente (mudança de nome, ex.: "... - EM LIQUIDAÇÃO EXTRAJUDICIAL"). Não são idênticas linha a linha.
Regra: manter 1 linha por grão no ODS (mesmos valores numéricos), registrar ALERTA em `CTL.Rejeicao`; nome oficial vem do CADOP.

## A4 — Fórmula do IGR
- Série viva (2021+): `IGR = reclamações / beneficiários × 100.000` exato a 2 casas.
- Série congelada: 13.272 linhas (2015–2018) divergem até ~0,05 → o valor publicado foi **arredondado a 1 casa**.
  Regra: o DW recalcula a taxa a partir de numerador/denominador (consistente em todos os períodos).
- `COMPETENCIA_BENEFICIARIO` = competência − 1 mês na série viva; = mesma competência na série congelada.

## A5 — Beneficiários muito pequenos geram IGR extremo
6.119 linhas com menos de 100 beneficiários. Ex.: operadora odontológica com **1** beneficiário e 91 reclamações → IGR 9.100.000.
Regra: volume mínimo (beneficiários e reclamações) para rankings/outliers; linhas preservadas e marcadas.

## A6 — Porte
Definição oficial (dicionário IGR): Pequeno < 20 mil, Médio 20–100 mil, Grande > 100 mil vínculos ativos no SIB.
O porte vem **por cobertura** (6.567 casos de operadora/competência com portes diferentes entre médica e odonto).
→ Porte e beneficiários disponíveis nas fontes obrigatórias; não é necessária fonte complementar.

## A7 — Integridade das chaves
Registro ANS sempre com 6 dígitos, sem caracteres não numéricos. **100%** dos registros de IGR e TR existem no CADOP
(ativas ∪ canceladas): IGR 892 ativas + 525 canceladas; TR 724 + 486. Nenhuma operadora "sem cadastro".
995 operadoras têm IGR e TR; 422 só IGR; 215 só TR.

## A8 — Segmentos (modalidade CADOP)
Ativas: Cooperativa Médica 262, Medicina de Grupo 251, Administradora de Benefícios 181, Autogestão 141,
Odontologia de Grupo 138 (+3 modalidades). Canceladas: 10 modalidades. Administradoras não têm IGR (nota técnica).
