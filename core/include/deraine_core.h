#ifndef DERAINE_CORE_H
#define DERAINE_CORE_H

#include <stdint.h>

#if defined(__cplusplus)
extern "C" {
#endif

// Initializes the core system. Returns 0 on success.
int32_t deraine_init(void);

// Returns the core version.
int32_t deraine_version(void);

// Creates a new database. Returns 0 on success, -1 on error.
int32_t deraine_create_db(const char* path);

// Opens an existing database. Returns 0 on success, -1 on error.
int32_t deraine_open_db(const char* path);

#if defined(__cplusplus)
}
#endif

#endif // DERAINE_CORE_H
