SHOW GLOBAL VARIABLES WHERE Variable_name IN (
 'version', 'version_comment', 'version_compile_machine', 'version_compile_os',
 'sql_mode', 'character_set_server', 'collation_server', 'default_storage_engine',
 'time_zone', 'system_time_zone', 'event_scheduler', 'lower_case_table_names',
 'explicit_defaults_for_timestamp', 'innodb_version', 'innodb_page_size',
 'innodb_buffer_pool_size', 'innodb_file_format', 'innodb_large_prefix',
 'innodb_file_per_table', 'innodb_strict_mode', 'innodb_flush_log_at_trx_commit',
 'innodb_log_file_size', 'innodb_log_files_in_group', 'innodb_doublewrite',
 'max_allowed_packet', 'max_connections', 'group_concat_max_len'
);
