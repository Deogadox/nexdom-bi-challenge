/* 02_create_stg_tables.sql — GERADO por src/loading/load_stg.py --emit-ddl a partir dos
   cabeçalhos reais dos arquivos da ANS. Colunas com o nome original; tudo NVARCHAR (cópia fiel). */
USE ANS_BI;
GO

-- Origem: data/raw/operadoras_ativas/Relatorio_cadop.csv (1,101 linhas no momento da geração)
IF OBJECT_ID(N'STG.ANS_Organizacoes_Ativas', N'U') IS NULL
CREATE TABLE STG.ANS_Organizacoes_Ativas (
    IdExecucao     INT           NOT NULL,
    NrLinhaArquivo INT           NOT NULL,   -- ordinal do registro no arquivo (cabeçalho = linha 1)
    ArquivoOrigem  NVARCHAR(260) NOT NULL,
    Sha256         CHAR(64)      NOT NULL,
    DtCarga        DATETIME2(0)  NOT NULL CONSTRAINT DF_STG_ANS_Organizacoes_Ativas_DtCarga DEFAULT SYSDATETIME(),
    [REGISTRO_OPERADORA] NVARCHAR(50) NULL,  -- máx. observado 6
    [CNPJ] NVARCHAR(50) NULL,  -- máx. observado 14
    [RAZAO_SOCIAL] NVARCHAR(300) NULL,  -- máx. observado 140
    [NOME_FANTASIA] NVARCHAR(150) NULL,  -- máx. observado 64
    [MODALIDADE] NVARCHAR(100) NULL,  -- máx. observado 33
    [LOGRADOURO] NVARCHAR(100) NULL,  -- máx. observado 40
    [NUMERO] NVARCHAR(50) NULL,  -- máx. observado 15
    [COMPLEMENTO] NVARCHAR(100) NULL,  -- máx. observado 40
    [BAIRRO] NVARCHAR(100) NULL,  -- máx. observado 30
    [CIDADE] NVARCHAR(100) NULL,  -- máx. observado 26
    [UF] NVARCHAR(50) NULL,  -- máx. observado 2
    [CEP] NVARCHAR(50) NULL,  -- máx. observado 8
    [DDD] NVARCHAR(50) NULL,  -- máx. observado 2
    [TELEFONE] NVARCHAR(50) NULL,  -- máx. observado 18
    [FAX] NVARCHAR(50) NULL,  -- máx. observado 11
    [ENDERECO_ELETRONICO] NVARCHAR(100) NULL,  -- máx. observado 47
    [REPRESENTANTE] NVARCHAR(100) NULL,  -- máx. observado 50
    [CARGO_REPRESENTANTE] NVARCHAR(100) NULL,  -- máx. observado 40
    [REGIAO_DE_COMERCIALIZACAO] NVARCHAR(50) NULL,  -- máx. observado 1
    [DATA_REGISTRO_ANS] NVARCHAR(50) NULL,  -- máx. observado 10
    CONSTRAINT PK_STG_ANS_Organizacoes_Ativas PRIMARY KEY CLUSTERED (IdExecucao, NrLinhaArquivo)
);
GO

-- Origem: data/raw/operadoras_canceladas/Relatorio_cadop_canceladas.csv (3,085 linhas no momento da geração)
IF OBJECT_ID(N'STG.ANS_Organizacoes_Canceladas', N'U') IS NULL
CREATE TABLE STG.ANS_Organizacoes_Canceladas (
    IdExecucao     INT           NOT NULL,
    NrLinhaArquivo INT           NOT NULL,   -- ordinal do registro no arquivo (cabeçalho = linha 1)
    ArquivoOrigem  NVARCHAR(260) NOT NULL,
    Sha256         CHAR(64)      NOT NULL,
    DtCarga        DATETIME2(0)  NOT NULL CONSTRAINT DF_STG_ANS_Organizacoes_Canceladas_DtCarga DEFAULT SYSDATETIME(),
    [REGISTRO_OPERADORA] NVARCHAR(50) NULL,  -- máx. observado 6
    [CNPJ] NVARCHAR(50) NULL,  -- máx. observado 14
    [RAZAO_SOCIAL] NVARCHAR(300) NULL,  -- máx. observado 140
    [NOME_FANTASIA] NVARCHAR(150) NULL,  -- máx. observado 64
    [MODALIDADE] NVARCHAR(100) NULL,  -- máx. observado 33
    [LOGRADOURO] NVARCHAR(100) NULL,  -- máx. observado 40
    [NUMERO] NVARCHAR(50) NULL,  -- máx. observado 19
    [COMPLEMENTO] NVARCHAR(100) NULL,  -- máx. observado 40
    [BAIRRO] NVARCHAR(100) NULL,  -- máx. observado 30
    [CIDADE] NVARCHAR(100) NULL,  -- máx. observado 28
    [UF] NVARCHAR(50) NULL,  -- máx. observado 2
    [CEP] NVARCHAR(50) NULL,  -- máx. observado 8
    [DDD] NVARCHAR(50) NULL,  -- máx. observado 3
    [TELEFONE] NVARCHAR(50) NULL,  -- máx. observado 20
    [FAX] NVARCHAR(50) NULL,  -- máx. observado 20
    [ENDERECO_ELETRONICO] NVARCHAR(150) NULL,  -- máx. observado 60
    [REPRESENTANTE] NVARCHAR(100) NULL,  -- máx. observado 50
    [CARGO_REPRESENTANTE] NVARCHAR(100) NULL,  -- máx. observado 40
    [REGIAO_DE_COMERCIALIZACAO] NVARCHAR(50) NULL,  -- máx. observado 1
    [DATA_REGISTRO_ANS] NVARCHAR(50) NULL,  -- máx. observado 10
    [DATA_DESCREDENCIAMENTO] NVARCHAR(50) NULL,  -- máx. observado 10
    [MOTIVO_DO_DESCREDENCIAMENTO] NVARCHAR(150) NULL,  -- máx. observado 60
    CONSTRAINT PK_STG_ANS_Organizacoes_Canceladas PRIMARY KEY CLUSTERED (IdExecucao, NrLinhaArquivo)
);
GO

-- Origem: data/raw/igr/pda-023-igr.csv (130,155 linhas no momento da geração)
IF OBJECT_ID(N'STG.ANS_IGR', N'U') IS NULL
CREATE TABLE STG.ANS_IGR (
    IdExecucao     INT           NOT NULL,
    NrLinhaArquivo INT           NOT NULL,   -- ordinal do registro no arquivo (cabeçalho = linha 1)
    ArquivoOrigem  NVARCHAR(260) NOT NULL,
    Sha256         CHAR(64)      NOT NULL,
    DtCarga        DATETIME2(0)  NOT NULL CONSTRAINT DF_STG_ANS_IGR_DtCarga DEFAULT SYSDATETIME(),
    [REGISTRO_OPERADORA] NVARCHAR(50) NULL,  -- máx. observado 6
    [RAZAO_SOCIAL] NVARCHAR(300) NULL,  -- máx. observado 140
    [COBERTURA] NVARCHAR(100) NULL,  -- máx. observado 27
    [IGR] NVARCHAR(50) NULL,  -- máx. observado 10
    [QTD_RECLAMACOES] NVARCHAR(50) NULL,  -- máx. observado 4
    [QTD_BENEFICIARIOS] NVARCHAR(50) NULL,  -- máx. observado 7
    [PORTE_OPERADORA] NVARCHAR(50) NULL,  -- máx. observado 7
    [COMPETENCIA] NVARCHAR(50) NULL,  -- máx. observado 7
    [COMPETENCIA_BENEFICIARIO] NVARCHAR(50) NULL,  -- máx. observado 7
    [DT_ATUALIZACAO] NVARCHAR(50) NULL,  -- máx. observado 10
    CONSTRAINT PK_STG_ANS_IGR PRIMARY KEY CLUSTERED (IdExecucao, NrLinhaArquivo)
);
GO

-- Origem: data/raw/tr/pda-048-taxa_de_resolutividade.csv (63,366 linhas no momento da geração)
IF OBJECT_ID(N'STG.ANS_TR', N'U') IS NULL
CREATE TABLE STG.ANS_TR (
    IdExecucao     INT           NOT NULL,
    NrLinhaArquivo INT           NOT NULL,   -- ordinal do registro no arquivo (cabeçalho = linha 1)
    ArquivoOrigem  NVARCHAR(260) NOT NULL,
    Sha256         CHAR(64)      NOT NULL,
    DtCarga        DATETIME2(0)  NOT NULL CONSTRAINT DF_STG_ANS_TR_DtCarga DEFAULT SYSDATETIME(),
    [CD_REGISTRO_ANS] NVARCHAR(50) NULL,  -- máx. observado 6
    [NM_RAZAO_SOCIAL] NVARCHAR(300) NULL,  -- máx. observado 140
    [TP_NATUREZA] NVARCHAR(50) NULL,  -- máx. observado 16
    [VL_TR] NVARCHAR(50) NULL,  -- máx. observado 6
    [NR_NUMERADOR] NVARCHAR(50) NULL,  -- máx. observado 4
    [NR_DENOMINADOR] NVARCHAR(50) NULL,  -- máx. observado 4
    [CD_COMPETENCIA] NVARCHAR(50) NULL,  -- máx. observado 7
    [DT_ATUALIZACAO] NVARCHAR(50) NULL,  -- máx. observado 10
    CONSTRAINT PK_STG_ANS_TR PRIMARY KEY CLUSTERED (IdExecucao, NrLinhaArquivo)
);
GO
