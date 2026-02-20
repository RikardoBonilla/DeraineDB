#ifndef DERAINE_CORE_H
#define DERAINE_CORE_H

#include <stdint.h>

int32_t deraine_init();
int32_t deraine_version(void);

void* deraine_open_db(const char* path);

void deraine_close_db(void* storage_ptr);

int32_t deraine_sync(void* storage_ptr);

int32_t deraine_write_vector(void* storage_ptr, uint64_t index, uint32_t tag, const float* data, uint32_t len);

int32_t deraine_read_vector(void* storage_ptr, uint64_t index, float* out_data, uint32_t out_len);

int32_t deraine_delete_vector(void* storage_ptr, uint64_t index);

int32_t deraine_search(void* storage_ptr, const float* query_ptr, uint32_t query_len, uint32_t filter_tag, uint32_t k, uint64_t* out_ids, float* out_distances, int32_t mode);

#ifdef __cplusplus
}
#endif
#endif
