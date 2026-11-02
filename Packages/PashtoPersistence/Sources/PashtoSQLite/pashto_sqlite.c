#include "pashto_sqlite.h"
#include <sqlite3.h>

void pashto_disable_checkpoint_on_close(void *database) {
    sqlite3_db_config(database, SQLITE_DBCONFIG_NO_CKPT_ON_CLOSE, 1, (int *)0);
}
