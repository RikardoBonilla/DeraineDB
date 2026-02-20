#ifndef DERAINE_CORE_H
#define DERAINE_CORE_H

#include <stdint.h>

int32_t deraine_init();
int32_t deraine_version();

void* deraine_open_db(const char* path);

void deraine_close_db(void* storage_ptr);

int32_t deraine_sync(void* storage_ptr);

int32_t deraine_write_vector(void* storage_ptr, uint64_t index, const float* data, uint32_t len);

#endif
