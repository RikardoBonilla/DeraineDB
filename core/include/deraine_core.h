#ifndef DERAINE_CORE_H
#define DERAINE_CORE_H

#include <stdint.h>

int32_t deraine_init();
int32_t deraine_version(void);

void* deraine_open_db(const char* path);

void deraine_close_db(void* storage_ptr);

int32_t deraine_sync(void* storage_ptr);

int32_t deraine_create_snapshot(void* storage_ptr, const char* target_path);

int32_t deraine_rebuild_index(void* storage_ptr);

typedef struct {
    uint8_t healthy;
    uint32_t version;
    uint64_t vector_count;
    int32_t max_level;
} deraine_status_t;

int32_t deraine_get_status(void* storage_ptr, deraine_status_t* out_status);

int32_t deraine_write_vector(void* storage_ptr, uint64_t index, uint64_t metadata_mask, const float* data, uint32_t len);

int32_t deraine_read_vector(void* storage_ptr, uint64_t index, float* out_data, uint32_t out_len);

int32_t deraine_delete_vector(void* storage_ptr, uint64_t index);

int32_t deraine_search(void* storage_ptr, const float* query_ptr, uint32_t query_len, uint64_t filter_mask, uint32_t k, uint64_t* out_ids, float* out_distances, int32_t mode);

#ifdef __cplusplus
}
#endif
#endif
