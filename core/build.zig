const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Definimos el módulo raíz
    const mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Usamos addLibrary con linkage .static en lugar de addStaticLibrary
    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "core",
        .root_module = mod,
    });

    // Instalamos el artefacto (libcore.a va a zig-out/lib)
    b.installArtifact(lib);

    // Instalamos el header manual
    const install_header = b.addInstallFile(b.path("include/lumina_core.h"), "include/lumina_core.h");
    b.getInstallStep().dependOn(&install_header.step);
}
