#ifndef DERAINE_CORE_H
#define DERAINE_CORE_H

#include <stdint.h>

// Base engine functions
int32_t deraine_init();
int32_t deraine_version();

// New Pointer-based Lifecycle
// Returns a pointer to the storage instance or NULL on failure
void* deraine_open_db(const char* path);

// Closes the database and releases all associated resources
void deraine_close_db(void* storage_ptr);

// Data operations using the storage handle
int32_t deraine_write_vector(void* storage_ptr, uint64_t index, const float* data, uint32_t len);

#endif
