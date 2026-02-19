#ifndef LUMINA_CORE_H
#define LUMINA_CORE_H

#include <stdint.h>

#if defined(__cplusplus)
extern "C" {
#endif

// Inicializa el sistema core. Retorna 0 si ok.
int32_t lumina_init(void);

// Retorna la versión del core.
int32_t lumina_version(void);

#if defined(__cplusplus)
}
#endif

#endif // LUMINA_CORE_H
