/**
 * The columns of `file_object`, as schema module 18 extends them.
 *
 * PostgREST cannot see `information_schema`, so the shape of the table cannot
 * be discovered at runtime. The catalogue below is the shape of the live
 * database; the row count shown beside it is read from the table itself, so
 * the number is always the number of rows this caller may see.
 */

/** One column of `file_object`. */
export type FileObjectColumn = {
  /** The column name. */
  name: string;
  /** The PostgreSQL data type. */
  type: string;
  /** Whether the column accepts null. */
  nullable: boolean;
};

/** The columns of `file_object`, in the order the database declares them. */
export const FILE_OBJECT_COLUMNS: FileObjectColumn[] = [
  { name: 'file_object_id', type: 'bigint', nullable: false },
  { name: 'storage_provider', type: 'character varying(30)', nullable: false },
  { name: 'storage_key', type: 'character varying(500)', nullable: false },
  { name: 'original_file_name', type: 'character varying(255)', nullable: false },
  { name: 'mime_type', type: 'character varying(100)', nullable: false },
  { name: 'file_size_bytes', type: 'bigint', nullable: false },
  { name: 'checksum_sha256', type: 'character(64)', nullable: true },
  { name: 'uploaded_at', type: 'timestamp with time zone', nullable: false },
  { name: 'stored_file_name', type: 'character varying(255)', nullable: true },
  { name: 'storage_url', type: 'character varying(1000)', nullable: true },
  { name: 'file_extension', type: 'character varying(20)', nullable: true },
  { name: 'confidentiality_level', type: 'text', nullable: false },
  { name: 'is_encrypted', type: 'boolean', nullable: false },
  { name: 'uploaded_by_user_id', type: 'bigint', nullable: true },
  { name: 'updated_at', type: 'timestamp with time zone', nullable: false },
  { name: 'deleted_at', type: 'timestamp with time zone', nullable: true },
  { name: 'encryption_key_reference', type: 'character varying(255)', nullable: true },
  { name: 'virus_scan_status', type: 'text', nullable: false },
  { name: 'virus_scanned_at', type: 'timestamp with time zone', nullable: true },
];
