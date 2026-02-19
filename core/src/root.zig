const std = @import("std");

// Importante: export para que aparezca en el header .h
export fn lumina_init() i32 {
    return 0; // Success
}

export fn lumina_version() i32 {
    return 1;
}
