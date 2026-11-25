/* Evidência do ODS: última execução, log por etapa, rejeições/alertas por regra e perfil das tabelas. */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
SET NOCOUNT ON;
DECLARE @Id INT = (SELECT MAX(IdExecucao) FROM CTL.Execucao WHERE Origem LIKE N'%Pipeline%' OR Origem LIKE N'run_local%');

SELECT IdExecucao, Origem, Status, DtInicio, DtFim, LEFT(Mensagem, 300) AS Mensagem FROM CTL.Execucao WHERE IdExecucao = @Id;

SELECT Etapa, Objeto, Status, LinhasLidas, LinhasInseridas, LinhasRejeitadas,
       DATEDIFF(MILLISECOND, DtInicio, DtFim) AS Ms, LEFT(Mensagem, 200) AS Mensagem
FROM CTL.LogEtapa WHERE IdExecucao = @Id ORDER BY IdLog;

SELECT Etapa, TabelaOrigem, Regra, Severidade, COUNT(*) AS Ocorrencias, COUNT(DISTINCT NrLinhaArquivo) AS Linhas
FROM CTL.Rejeicao WHERE IdExecucao = @Id
GROUP BY Etapa, TabelaOrigem, Regra, Severidade ORDER BY Etapa, TabelaOrigem, Severidade, Regra;

SELECT N'ODS.Organizacoes' AS Tabela, Situacao AS Recorte, COUNT(*) AS Linhas FROM ODS.Organizacoes GROUP BY Situacao
UNION ALL SELECT N'ODS.IGR', CONCAT(SerieIGR, N' ', FORMAT(MIN(Competencia), 'yyyy-MM'), N'..', FORMAT(MAX(Competencia), 'yyyy-MM')), COUNT(*) FROM ODS.IGR GROUP BY SerieIGR
UNION ALL SELECT N'ODS.TR', CONCAT(Natureza, N' ', FORMAT(MIN(Competencia), 'yyyy-MM'), N'..', FORMAT(MAX(Competencia), 'yyyy-MM')), COUNT(*) FROM ODS.TR GROUP BY Natureza;

SELECT Modalidade, Situacao, COUNT(*) AS Operadoras FROM ODS.Organizacoes GROUP BY Modalidade, Situacao ORDER BY Modalidade, Situacao;
