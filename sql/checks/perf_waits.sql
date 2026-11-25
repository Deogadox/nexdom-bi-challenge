/* Confirma a causa da lentidão: esperas acumuladas por concessão de memória e bloqueio, e memória da instância. */
SET NOCOUNT ON;
SELECT wait_type, waiting_tasks_count, CAST(wait_time_ms / 1000.0 AS DECIMAL(12,1)) AS espera_s,
       CAST(max_wait_time_ms / 1000.0 AS DECIMAL(12,1)) AS maior_espera_s
FROM sys.dm_os_wait_stats
WHERE wait_type IN (N'RESOURCE_SEMAPHORE', N'RESOURCE_SEMAPHORE_QUERY_COMPILE', N'PAGEIOLATCH_SH', N'PAGEIOLATCH_EX', N'WRITELOG', N'IO_COMPLETION')
   OR wait_type LIKE N'LCK[_]M[_]%'
ORDER BY wait_time_ms DESC;
SELECT name, value_in_use FROM sys.configurations WHERE name IN (N'max server memory (MB)', N'min memory per query (KB)');
SELECT physical_memory_kb / 1024 AS memoria_fisica_mb, committed_target_kb / 1024 AS alvo_sql_mb FROM sys.dm_os_sys_info;
SELECT name, compatibility_level FROM sys.databases WHERE name = DB_NAME();
