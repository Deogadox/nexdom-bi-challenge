# Dicionário de dados (ODS, DW e controle)

As colunas da STG têm os nomes originais dos arquivos da ANS, todas em `NVARCHAR`, mais 5 colunas de controle
(`IdExecucao`, `NrLinhaArquivo`, `ArquivoOrigem`, `Sha256`, `DtCarga`). Veja `sql/02_create_stg_tables.sql` e os
dicionários oficiais em `data/raw/<fonte>/*.ods`.

## ODS
### `ODS.Organizacoes` — 1 linha por registro ANS (ativas ∪ canceladas)
| Coluna | Tipo | Descrição |
|---|---|---|
| `RegistroANS` | CHAR(6) PK | registro da operadora na ANS, com zeros à esquerda |
| `CNPJ` | CHAR(14) | nulo se inválido (alerta `CNPJ_INVALIDO`) |
| `RazaoSocial`, `NomeFantasia` | NVARCHAR | sem espaços nas pontas |
| `Modalidade` | NVARCHAR(60) | valor original do CADOP (segmento) |
| `UF`, `Cidade`, `RegiaoComercializacao` | — | localização e região de comercialização (1 a 6) |
| `DtRegistroANS`, `DtDescredenciamento`, `MotivoDescredenciamento` | DATE / NVARCHAR | as duas últimas só para canceladas |
| `Situacao` | VARCHAR(9) | `ATIVA` \| `CANCELADA` |
| `TabelaOrigem`, `NrLinhaArquivo`, `IdExecucaoODS` | — | rastreio até a linha da STG e do arquivo |

### `ODS.IGR` — registro × cobertura × competência
| Coluna | Tipo | Descrição |
|---|---|---|
| `RegistroANS`, `Cobertura`, `Competencia` | PK | cobertura ∈ {Assistência médica, Exclusivamente odontológica}; competência = 1º dia do mês das reclamações |
| `CompetenciaBeneficiario` | DATE | mês do denominador (mês anterior na série vigente) |
| `QtdReclamacoes`, `QtdBeneficiarios` | INT | numerador (demandas NIP) e denominador (vínculos ativos) |
| `IGRPublicado` | DECIMAL(18,2) | valor publicado (a série congelada vem arredondada a 1 casa) |
| `PorteOperadora` | NVARCHAR(7) | Pequeno (< 20 mil) · Médio (20–100 mil) · Grande (> 100 mil) |
| `SerieIGR` | VARCHAR(9) | `CONGELADA` (`DT_ATUALIZACAO` vazio) \| `VIGENTE` |
| `FlCadastroEncontrado`, `FlIGRDivergente` | BIT | correspondência no cadastro; publicado ≠ recalculado além da tolerância |

### `ODS.TR` — registro × natureza × competência
| Coluna | Tipo | Descrição |
|---|---|---|
| `RegistroANS`, `Natureza`, `Competencia` | PK | natureza ∈ {Assistencial, Não Assistencial, Geral}; **Geral = A + N** |
| `Numerador` | INT | demandas Inativa + NP + RVE |
| `Denominador` | INT | Inativa + NP + RVE + Núcleo (> 0) |
| `VlTRPublicado` | DECIMAL(9,2) | TR publicada (%) |

## DW (modelo estrela)
| Tabela | Chave | Colunas principais |
|---|---|---|
| `DimOperadora` | `SkOperadora` (−1 = não informada) | `RegistroANS`, `CNPJ`, `RazaoSocial`, `NomeFantasia`, `NomeExibicao` ("nome (registro)"), `SkSegmento`, `UF`, `Cidade`, `Situacao`, datas |
| `DimSegmento` | `SkSegmento` | `Modalidade`, `Segmento`, `GrupoAssistencial` (Médico-hospitalar \| Odontológico \| Administradora), `FlModalidadeLegada` |
| `DimTempo` | `SkTempo` (AAAAMM) | `DataMes`, `Ano`, `Mes`, `NomeMes`, `AnoMes`, `Trimestre`, `Semestre`, `FlIGRDisponivel`, `FlTRDisponivel`, `FlJanelaComumIGRTR`, `SerieIGR` |
| `DimCobertura` | `SkCobertura` (0 = não informada) | `Cobertura` |
| `DimNatureza` | `SkNatureza` (0 = não informada) | `Natureza`, `FlTotal` (1 = Geral) |
| `DimPorte` | `SkPorte` (0 = não informado) | `Porte`, `Ordem`, `FaixaBeneficiarios` |
| `FatoIGR` | `SkOperadora` + `SkCobertura` + `SkTempo` | `SkPorte`, `SkTempoBeneficiario`, `QtdReclamacoes`, `QtdBeneficiarios`, `IGRPublicado`, `IGRCalculado` (persistida), `FlIGRDivergente` |
| `FatoTR` | `SkOperadora` + `SkNatureza` + `SkTempo` | `Numerador`, `Denominador`, `VlTRPublicado` |
| `AnaliseR2Operadora` | `SkOperadora` + `SkCobertura` | janela, `Reclamacoes`, `BenefSoma`, `BenefMedio`, `Meses`, `IGR`, `PorteUltimoMes`, `Elegivel`, `Esperado`, `ZFunil`, `LimInfIGR`, `LimSupIGR`, `Funil`, `IQRSegmento`, `ZRobSegmento`, `OutlierConsistente` |
| `AnaliseR1Operadora` | `SkOperadora` | `GrupoAssistencial`, `IGR`, `Demandas`, `Resolvidas`, `TRGeral`, `TRAssistencial`, `TRNaoAssistencial`, `Elegivel`, `ScoreIGR`, `ScoreTR`, `IndiceCombinado`, `Quadrante` |

**Regras de leitura:** IGR = Σ`QtdReclamacoes` / Σ`QtdBeneficiarios` × 100.000; TR = Σ`Numerador` / Σ`Denominador`.
Nunca somar a natureza `Geral` com as demais. Nunca calcular a média de `IGRCalculado` ou de `IGR`.
Critérios de `Elegivel` e significado dos scores: [`resultados_analises.md`](resultados_analises.md).

## Controle (`CTL`)
| Tabela | Colunas principais |
|---|---|
| `Execucao` | `IdExecucao`, `Origem`, `DtInicio`, `DtFim`, `Status`, `Usuario`, `Mensagem` |
| `LogEtapa` | `IdLog`, `IdExecucao`, `Etapa`, `Objeto`, `DtInicio`, `DtFim`, `LinhasLidas`, `LinhasInseridas`, `LinhasAtualizadas`, `LinhasRejeitadas`, `Status`, `Mensagem`, `ErroNumero`, `ErroLinha` |
| `ArquivoCarregado` | `IdArquivo`, `IdExecucao`, `Fonte`, `NomeArquivo`, `CaminhoRelativo`, `UrlOrigem`, `Sha256`, `Bytes`, `Encoding`, `ServerLastModified`, `DtDownloadUtc`, `TabelaDestino`, `QtdLinhas`, `DtCarga` |
| `Rejeicao` | `IdRejeicao`, `IdExecucao`, `Etapa`, `TabelaOrigem`, `NrLinhaArquivo`, `ChaveNatural`, `Regra`, `Coluna`, `ValorOriginal`, `Severidade` (`ERRO`/`ALERTA`) |
