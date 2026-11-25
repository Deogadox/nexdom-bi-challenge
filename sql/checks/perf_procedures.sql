/* Diagnóstico de desempenho por instrução das procedures do ODS, via Query Store
   (persistente; ativo por padrão em bancos novos no SQL Server 2022). */
SET NOCOUNT ON;
SELECT actual_state_desc AS QueryStore, readonly_reason FROM sys.database_query_store_options;

SELECT TOP (15)
       OBJECT_NAME(q.object_id) AS Procedimento,
       SUM(rs.count_executions) AS Execucoes,
       CAST(MAX(rs.last_duration) / 1000.0 AS DECIMAL(12,1)) AS UltimaMs,
       CAST(MAX(rs.last_cpu_time) / 1000.0 AS DECIMAL(12,1)) AS UltimaCpuMs,
       MAX(rs.last_logical_io_reads) AS UltimasLeituras,
       MAX(rs.last_rowcount) AS UltimasLinhas,
       LEFT(REPLACE(REPLACE(qt.query_sql_text, CHAR(13), ' '), CHAR(10), ' '), 200) AS Instrucao
FROM sys.query_store_query q
JOIN sys.query_store_query_text qt ON qt.query_text_id = q.query_text_id
JOIN sys.query_store_plan p ON p.query_id = q.query_id
JOIN sys.query_store_runtime_stats rs ON rs.plan_id = p.plan_id
WHERE OBJECT_NAME(q.object_id) LIKE N'usp[_]ODS[_]%'
GROUP BY q.object_id, q.query_id, qt.query_sql_text
ORDER BY MAX(rs.last_duration) DESC;
