# Regras de tratamento (STG → ODS)

Implementadas em `sql/05_ods_stored_procedures.sql`. Severidades em `CTL.Rejeicao`:
**ERRO** = a linha não segue para o ODS (permanece na STG, com o motivo registrado);
**ALERTA** = a linha segue, com o campo nulo ou uma flag. Nenhuma linha some sem registro:
`usp_ODS_Validacao` exige `linhas STG = linhas ODS + linhas descartadas` e interrompe o pipeline se falhar.

## Comuns
| Regra | Severidade | Tratamento |
|---|---|---|
| Registro ANS vazio, não numérico ou com mais de 6 dígitos | ERRO `REGISTRO_ANS_INVALIDO` | — |
| Registro ANS válido | — | `TRIM` + zeros à esquerda → `CHAR(6)` (ex.: `515` → `000515`) |
| Textos | — | `TRIM`; vazio → `NULL` |
| Números | — | decimal com vírgula → ponto; `TRY_CONVERT`; falha → ERRO `NUMERO_INVALIDO` |
| Competência `AAAA-MM` | ERRO `COMPETENCIA_INVALIDA` se não converter | `DATE` no 1º dia do mês |
| Registro sem correspondência no cadastro (ativas ∪ canceladas) | ALERTA `REGISTRO_SEM_CADASTRO` | segue com `FlCadastroEncontrado = 0` |

## ODS.Organizacoes (CADOP ativas ∪ canceladas)
- Razão social ou modalidade ausente → ERRO `CAMPO_OBRIGATORIO_AUSENTE`.
- CNPJ diferente de 14 dígitos → ALERTA `CNPJ_INVALIDO` (campo `NULL`). Datas inválidas → ALERTA `DATA_INVALIDA`.
- Mesmo registro nas duas listas: **a ativa prevalece**; as demais versões viram ALERTA `DUPLICIDADE_DESCARTADA`.
- `Modalidade` é mantida como veio (inclusive os nomes antigos "Administradora" e "Seguradora"); o agrupamento em segmentos é feito no DW.
- Colunas de contato (endereço, telefone, e-mail, representante) ficam só na STG: não são usadas na análise.

## ODS.IGR
- Domínios: cobertura ∈ {Assistência médica, Exclusivamente odontológica}; porte ∈ {Pequeno, Médio, Grande}
  (porte inválido → ALERTA com `NULL`; cobertura inválida → ERRO).
- `SerieIGR = CONGELADA` quando `DT_ATUALIZACAO` está vazio (definição do dicionário oficial), senão `VIGENTE`.
- Duplicidade no grão (registro × cobertura × competência):
  - mesmas métricas, nome diferente → mantém a 1ª linha do arquivo; demais: ALERTA `DUPLICIDADE_DESCARTADA`;
  - métricas diferentes → todas as linhas do grão: ERRO `DUPLICIDADE_CONFLITANTE` (não há critério seguro de escolha).
- `FlIGRDivergente`: |IGR publicado − reclamações/beneficiários×100.000| acima da tolerância da série →
  ALERTA `IGR_PUBLICADO_DIVERGENTE`. Tolerâncias: **VIGENTE 0,0051** (publicada com 2 casas) e **CONGELADA 0,06**
  (publicada com 1 casa; na execução 2 os 810 desvios acima de 0,05 ficaram todos entre 0,050 e 0,055).
  O DW sempre recalcula a taxa a partir de numerador e denominador.
- Beneficiários = 0 → ALERTA `DENOMINADOR_ZERO` (linha mantida; taxa indefinida no DW).

## ODS.TR
- Natureza ∈ {Assistencial, Não Assistencial, Geral}. **Geral é o total pré-agregado** (Geral = A + N) — no DW
  nunca somar as três.
- Numerador < 0, denominador ≤ 0 ou numerador > denominador → ERRO.
- |VL_TR publicado − numerador/denominador×100| > 0,0051 → ALERTA `TR_PUBLICADA_DIVERGENTE`.
- Validação R2: `Geral ≠ Assistencial + Não Assistencial` → ALERTA `TR_GERAL_INCONSISTENTE`.

## Reprocessamento
A STG guarda só a carga vigente (a ANS republica o histórico completo, com revisões). Cada procedure do ODS
apaga as rejeições da própria execução/tabela, reconstrói o alvo (`TRUNCATE` + `INSERT`) e confirma tudo numa
única transação. Uma falha desfaz a etapa inteira e fica registrada em `CTL.LogEtapa`.
