/* Diagnóstico de desempenho: tempo por instrução das procedures do pipeline (cache de planos).
   Mostra a última execução e o total acumulado de cada statement, do mais caro para o mais barato. */
SET NOCOUNT ON;
SELECT OBJECT_NAME(st.objectid, st.dbid) AS Procedimento,
       qs.execution_count AS Execucoes,
       CAST(qs.last_elapsed_time / 1000.0 AS DECIMAL(12,1)) AS UltimaMs,
       CAST(qs.last_worker_time  / 1000.0 AS DECIMAL(12,1)) AS UltimaCpuMs,
       qs.last_logical_reads AS UltimasLeituras,
       qs.last_rows AS UltimasLinhas,
       qs.last_spills AS UltimosSpills,
       LEFT(REPLACE(REPLACE(SUBSTRING(st.text, qs.statement_start_offset / 2 + 1,
            (CASE qs.statement_end_offset WHEN -1 THEN DATALENGTH(st.text) ELSE qs.statement_end_offset END
             - qs.statement_start_offset) / 2 + 1), CHAR(13), ' '), CHAR(10), ' '), 160) AS Instrucao
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
WHERE st.dbid = DB_ID() AND OBJECT_NAME(st.objectid, st.dbid) LIKE N'usp[_]ODS[_]%'
ORDER BY qs.last_elapsed_time DESC
OFFSET 0 ROWS FETCH NEXT 15 ROWS ONLY;

SELECT session_id, wait_type, wait_time, blocking_session_id FROM sys.dm_exec_requests WHERE database_id = DB_ID() AND session_id <> @@SPID;
