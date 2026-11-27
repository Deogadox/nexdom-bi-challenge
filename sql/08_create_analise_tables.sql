/* =====================================================================================
   08_create_analise_tables.sql — Resultados estatísticos publicados no DW (consumo do Power BI)
   Calculados uma única vez em src/analysis/analises.py e gravados por src/analysis/publicar_analises.py,
   para não duplicar a lógica estatística em SQL e DAX.
     DW.AnaliseR2Operadora : IGR atual (12 meses, série vigente) — operadora × cobertura
     DW.AnaliseR1Operadora : IGR × TR (mai/2018–abr/2019) — operadora (cobertura própria do segmento)
     DW.AnaliseCorrelacao  : correlações de Spearman/Pearson entre porte, reclamações, IGR e TR (tabela desconectada)
   Relacionam-se com DW.DimOperadora (e DimCobertura) no modelo do Power BI.
   ===================================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
USE ANS_BI;
GO
IF OBJECT_ID(N'DW.AnaliseR2Operadora', N'U') IS NULL
CREATE TABLE DW.AnaliseR2Operadora (
    SkOperadora        INT            NOT NULL CONSTRAINT FK_DW_AR2_Operadora REFERENCES DW.DimOperadora(SkOperadora),
    SkCobertura        TINYINT        NOT NULL CONSTRAINT FK_DW_AR2_Cobertura REFERENCES DW.DimCobertura(SkCobertura),
    JanelaInicio       INT            NOT NULL,     -- AAAAMM
    JanelaFim          INT            NOT NULL,
    Reclamacoes        INT            NOT NULL,
    BenefSoma          BIGINT         NOT NULL,
    BenefMedio         DECIMAL(14,1)  NOT NULL,
    Meses              TINYINT        NOT NULL,
    IGR                DECIMAL(12,4)  NULL,
    PorteUltimoMes     NVARCHAR(25)   NOT NULL,
    Elegivel           BIT            NOT NULL,     -- 12 meses e ≥ 5 mil beneficiários médios
    Esperado           DECIMAL(14,4)  NULL,         -- reclamações esperadas à taxa do mercado
    ZFunil             DECIMAL(10,4)  NULL,         -- z ajustado por sobredispersão
    LimInfIGR          DECIMAL(12,4)  NULL,
    LimSupIGR          DECIMAL(12,4)  NULL,
    Funil              NVARCHAR(20)   NOT NULL,     -- Dentro | Acima (pior) | Abaixo (melhor)
    IQRSegmento        NVARCHAR(10)   NOT NULL,     -- Acima | Abaixo | Dentro | n/a
    ZRobSegmento       DECIMAL(10,4)  NULL,
    OutlierConsistente BIT            NOT NULL,
    DtPublicacao       DATETIME2(0)   NOT NULL CONSTRAINT DF_DW_AR2_Dt DEFAULT SYSDATETIME(),
    CONSTRAINT PK_DW_AnaliseR2Operadora PRIMARY KEY (SkOperadora, SkCobertura)
);
GO
IF OBJECT_ID(N'DW.AnaliseR1Operadora', N'U') IS NULL
CREATE TABLE DW.AnaliseR1Operadora (
    SkOperadora        INT            NOT NULL CONSTRAINT PK_DW_AnaliseR1Operadora PRIMARY KEY
                                      CONSTRAINT FK_DW_AR1_Operadora REFERENCES DW.DimOperadora(SkOperadora),
    SkCobertura        TINYINT        NOT NULL CONSTRAINT FK_DW_AR1_Cobertura REFERENCES DW.DimCobertura(SkCobertura),
    GrupoAssistencial  NVARCHAR(30)   NOT NULL,
    JanelaInicio       INT            NOT NULL,
    JanelaFim          INT            NOT NULL,
    Reclamacoes        INT            NOT NULL,
    BenefMedio         DECIMAL(14,1)  NOT NULL,
    IGR                DECIMAL(12,4)  NULL,
    Demandas           INT            NULL,         -- denominador da TR (Geral)
    Resolvidas         INT            NULL,
    TRGeral            DECIMAL(9,4)   NULL,
    TRAssistencial     DECIMAL(9,4)   NULL,
    TRNaoAssistencial  DECIMAL(9,4)   NULL,
    Elegivel           BIT            NOT NULL,     -- + ≥ 30 demandas NIP no período
    ScoreIGR           DECIMAL(7,3)   NULL,         -- 100 × (1 − percentil do IGR no grupo)
    ScoreTR            DECIMAL(7,3)   NULL,         -- 100 × percentil da TR no grupo
    IndiceCombinado    DECIMAL(7,3)   NULL,         -- 0,5 × ScoreIGR + 0,5 × ScoreTR (pesos ajustáveis no DAX)
    Quadrante          NVARCHAR(40)   NULL,
    DtPublicacao       DATETIME2(0)   NOT NULL CONSTRAINT DF_DW_AR1_Dt DEFAULT SYSDATETIME()
);
GO
IF OBJECT_ID(N'DW.AnaliseCorrelacao', N'U') IS NULL
CREATE TABLE DW.AnaliseCorrelacao (
    IdCorrelacao       TINYINT        NOT NULL CONSTRAINT PK_DW_AnaliseCorrelacao PRIMARY KEY,
    Recorte            NVARCHAR(5)    NOT NULL,     -- R1 (2018–19, IGR × TR) | R2 (atual, IGR)
    Filtro             NVARCHAR(60)   NOT NULL,
    Par                NVARCHAR(60)   NOT NULL,
    VariavelX          NVARCHAR(30)   NOT NULL,
    VariavelY          NVARCHAR(30)   NOT NULL,
    N                  INT            NOT NULL,
    SpearmanRho        DECIMAL(6,3)   NOT NULL,
    SpearmanP          FLOAT          NOT NULL,
    PearsonR           DECIMAL(6,3)   NOT NULL,
    PearsonP           FLOAT          NOT NULL,
    TransformacaoPearson NVARCHAR(20) NOT NULL,     -- log aplicado só às variáveis assimétricas
    Forca              NVARCHAR(15)   NOT NULL,     -- |ρ| ≥ 0,7 forte · ≥ 0,4 moderada · ≥ 0,2 fraca · < 0,2 muito fraca
    Significativo      BIT            NOT NULL,     -- p de Spearman < 0,05
    DtPublicacao       DATETIME2(0)   NOT NULL CONSTRAINT DF_DW_ACor_Dt DEFAULT SYSDATETIME()
);
GO
PRINT N'08_create_analise_tables.sql concluído.';
