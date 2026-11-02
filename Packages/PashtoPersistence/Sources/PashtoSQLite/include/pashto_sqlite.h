#ifndef PASHto_SQLITE_H
#define PASHto_SQLITE_H

/// `sqlite3_db_config` is a variadic C function. The Swift overlay marks it
/// unavailable, so the no-checkpoint-on-close flag is set here.
void pashto_disable_checkpoint_on_close(void *database);

#endif
