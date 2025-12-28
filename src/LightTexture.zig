const std = @import("std");
const gl = @import("gl");
const Chunk = @import("Chunk.zig");

const LightTexture = @This();

handle: gl.uint,
descriptor: gl.uint64,

pub fn init() LightTexture {
    var handle: gl.uint = undefined;
    gl.CreateTextures(gl.TEXTURE_3D, 1, @ptrCast(&handle));
    gl.TextureStorage3D(handle, 1, gl.RGBA4, Chunk.SIZE + 2, Chunk.SIZE + 2, Chunk.SIZE + 2);

    gl.TextureParameteri(handle, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.TextureParameteri(handle, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.TextureParameteri(handle, gl.TEXTURE_WRAP_R, gl.CLAMP_TO_EDGE);
    gl.TextureParameteri(handle, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.TextureParameteri(handle, gl.TEXTURE_MAG_FILTER, gl.LINEAR);

    const descriptor = gl.GetTextureHandleARB(handle);
    if (descriptor == 0) std.debug.panic("Failed to create texture descriptor", .{});

    gl.MakeTextureHandleResidentARB(descriptor);

    return .{
        .handle = handle,
        .descriptor = descriptor,
    };
}

pub fn uploadMainVolume(light_texture: LightTexture, chunk: *Chunk) void {
    gl.TextureSubImage3D(
        light_texture.handle,
        0,
        1,
        1,
        1,
        Chunk.SIZE,
        Chunk.SIZE,
        Chunk.SIZE,
        gl.RGBA,
        gl.UNSIGNED_SHORT_4_4_4_4,
        @ptrCast(chunk.light),
    );
}

pub fn uploadWestOverlap(light_texture: LightTexture, neighbor_chunk_or_null: ?*Chunk) void {
    if (neighbor_chunk_or_null) |neighbor_chunk| {
        for (0..Chunk.SIZE) |y| {
            for (0..Chunk.SIZE) |z| {
                const light = neighbor_chunk.getLight(.{ .x = Chunk.EDGE, .y = @intCast(y), .z = @intCast(z) });

                gl.TextureSubImage3D(
                    light_texture.handle,
                    0,
                    0,
                    @intCast(y + 1),
                    @intCast(z + 1),
                    1,
                    1,
                    1,
                    gl.RGBA,
                    gl.UNSIGNED_SHORT_4_4_4_4,
                    @ptrCast(&light),
                );
            }
        }
    } else {
        // fill with black
    }
}

pub fn uploadBottomWestOverlap(light_texture: LightTexture, neighbor_chunk_or_null: ?*Chunk) void {
    if (neighbor_chunk_or_null) |neighbor_chunk| {
        for (0..Chunk.SIZE) |z| {
            const light = neighbor_chunk.getLight(.{ .x = Chunk.EDGE, .y = Chunk.EDGE, .z = @intCast(z) });

            gl.TextureSubImage3D(
                light_texture.handle,
                0,
                0,
                0,
                @intCast(z + 1),
                1,
                1,
                1,
                gl.RGBA,
                gl.UNSIGNED_SHORT_4_4_4_4,
                @ptrCast(&light),
            );
        }
    } else {
        // fill with black
    }
}

pub fn uploadTopWestOverlap(light_texture: LightTexture, neighbor_chunk_or_null: ?*Chunk) void {
    if (neighbor_chunk_or_null) |neighbor_chunk| {
        for (0..Chunk.SIZE) |z| {
            const light = neighbor_chunk.getLight(.{ .x = Chunk.EDGE, .y = 0, .z = @intCast(z) });

            gl.TextureSubImage3D(
                light_texture.handle,
                0,
                0,
                Chunk.SIZE + 1,
                @intCast(z + 1),
                1,
                1,
                1,
                gl.RGBA,
                gl.UNSIGNED_SHORT_4_4_4_4,
                @ptrCast(&light),
            );
        }
    } else {
        // fill with black
    }
}

pub fn uploadEastOverlap(light_texture: LightTexture, neighbor_chunk_or_null: ?*Chunk) void {
    if (neighbor_chunk_or_null) |neighbor_chunk| {
        for (0..Chunk.SIZE) |y| {
            for (0..Chunk.SIZE) |z| {
                const light = neighbor_chunk.getLight(.{ .x = 0, .y = @intCast(y), .z = @intCast(z) });

                gl.TextureSubImage3D(
                    light_texture.handle,
                    0,
                    Chunk.SIZE + 1,
                    @intCast(y + 1),
                    @intCast(z + 1),
                    1,
                    1,
                    1,
                    gl.RGBA,
                    gl.UNSIGNED_SHORT_4_4_4_4,
                    @ptrCast(&light),
                );
            }
        }
    } else {
        // fill with black
    }
}

pub fn uploadBottomEastOverlap(light_texture: LightTexture, neighbor_chunk_or_null: ?*Chunk) void {
    if (neighbor_chunk_or_null) |neighbor_chunk| {
        for (0..Chunk.SIZE) |z| {
            const light = neighbor_chunk.getLight(.{ .x = 0, .y = Chunk.EDGE, .z = @intCast(z) });

            gl.TextureSubImage3D(
                light_texture.handle,
                0,
                Chunk.SIZE + 1,
                0,
                @intCast(z + 1),
                1,
                1,
                1,
                gl.RGBA,
                gl.UNSIGNED_SHORT_4_4_4_4,
                @ptrCast(&light),
            );
        }
    } else {
        // fill with black
    }
}

pub fn uploadTopEastOverlap(light_texture: LightTexture, neighbor_chunk_or_null: ?*Chunk) void {
    if (neighbor_chunk_or_null) |neighbor_chunk| {
        for (0..Chunk.SIZE) |z| {
            const light = neighbor_chunk.getLight(.{ .x = 0, .y = 0, .z = @intCast(z) });

            gl.TextureSubImage3D(
                light_texture.handle,
                0,
                Chunk.SIZE + 1,
                Chunk.SIZE + 1,
                @intCast(z + 1),
                1,
                1,
                1,
                gl.RGBA,
                gl.UNSIGNED_SHORT_4_4_4_4,
                @ptrCast(&light),
            );
        }
    } else {
        // fill with black
    }
}

pub fn uploadNorthOverlap(light_texture: LightTexture, neighbor_chunk_or_null: ?*Chunk) void {
    if (neighbor_chunk_or_null) |neighbor_chunk| {
        const local_pos: Chunk.LocalPos = .{ .x = 0, .y = 0, .z = Chunk.EDGE };

        gl.TextureSubImage3D(
            light_texture.handle,
            0,
            1,
            1,
            0,
            Chunk.SIZE,
            Chunk.SIZE,
            1,
            gl.RGBA,
            gl.UNSIGNED_SHORT_4_4_4_4,
            @ptrCast(neighbor_chunk.light[local_pos.idx()..]),
        );
    } else {
        // fill with black
    }
}

pub fn uploadBottomNorthOverlap(light_texture: LightTexture, neighbor_chunk_or_null: ?*Chunk) void {
    if (neighbor_chunk_or_null) |neighbor_chunk| {
        const local_pos: Chunk.LocalPos = .{ .x = 0, .y = Chunk.EDGE, .z = Chunk.EDGE };

        gl.TextureSubImage3D(
            light_texture.handle,
            0,
            1,
            0,
            0,
            Chunk.SIZE,
            1,
            1,
            gl.RGBA,
            gl.UNSIGNED_SHORT_4_4_4_4,
            @ptrCast(neighbor_chunk.light[local_pos.idx()..]),
        );
    } else {
        // fill with black
    }
}

pub fn uploadTopNorthOverlap(light_texture: LightTexture, neighbor_chunk_or_null: ?*Chunk) void {
    if (neighbor_chunk_or_null) |neighbor_chunk| {
        const local_pos: Chunk.LocalPos = .{ .x = 0, .y = 0, .z = Chunk.EDGE };

        gl.TextureSubImage3D(
            light_texture.handle,
            0,
            1,
            Chunk.SIZE + 1,
            0,
            Chunk.SIZE,
            1,
            1,
            gl.RGBA,
            gl.UNSIGNED_SHORT_4_4_4_4,
            @ptrCast(neighbor_chunk.light[local_pos.idx()..]),
        );
    } else {
        // fill with black
    }
}

pub fn uploadSouthOverlap(light_texture: LightTexture, neighbor_chunk_or_null: ?*Chunk) void {
    if (neighbor_chunk_or_null) |neighbor_chunk| {
        const local_pos: Chunk.LocalPos = .{ .x = 0, .y = 0, .z = 0 };

        gl.TextureSubImage3D(
            light_texture.handle,
            0,
            1,
            1,
            Chunk.SIZE + 1,
            Chunk.SIZE,
            Chunk.SIZE,
            1,
            gl.RGBA,
            gl.UNSIGNED_SHORT_4_4_4_4,
            @ptrCast(neighbor_chunk.light[local_pos.idx()..]),
        );
    } else {
        // fill with black
    }
}

pub fn uploadBottomSouthOverlap(light_texture: LightTexture, neighbor_chunk_or_null: ?*Chunk) void {
    if (neighbor_chunk_or_null) |neighbor_chunk| {
        const local_pos: Chunk.LocalPos = .{ .x = 0, .y = Chunk.EDGE, .z = 0 };

        gl.TextureSubImage3D(
            light_texture.handle,
            0,
            1,
            0,
            Chunk.SIZE + 1,
            Chunk.SIZE,
            1,
            1,
            gl.RGBA,
            gl.UNSIGNED_SHORT_4_4_4_4,
            @ptrCast(neighbor_chunk.light[local_pos.idx()..]),
        );
    } else {
        // fill with black
    }
}

pub fn uploadTopSouthOverlap(light_texture: LightTexture, neighbor_chunk_or_null: ?*Chunk) void {
    if (neighbor_chunk_or_null) |neighbor_chunk| {
        const local_pos: Chunk.LocalPos = .{ .x = 0, .y = 0, .z = 0 };

        gl.TextureSubImage3D(
            light_texture.handle,
            0,
            1,
            Chunk.SIZE + 1,
            Chunk.SIZE + 1,
            Chunk.SIZE,
            1,
            1,
            gl.RGBA,
            gl.UNSIGNED_SHORT_4_4_4_4,
            @ptrCast(neighbor_chunk.light[local_pos.idx()..]),
        );
    } else {
        // fill with black
    }
}

pub fn uploadNorthWestOverlap(light_texture: LightTexture, neighbor_chunk_or_null: ?*Chunk) void {
    if (neighbor_chunk_or_null) |neighbor_chunk| {
        for (0..Chunk.SIZE) |y| {
            const light = neighbor_chunk.getLight(.{ .x = Chunk.EDGE, .y = @intCast(y), .z = Chunk.EDGE });

            gl.TextureSubImage3D(
                light_texture.handle,
                0,
                0,
                @intCast(y + 1),
                0,
                1,
                1,
                1,
                gl.RGBA,
                gl.UNSIGNED_SHORT_4_4_4_4,
                @ptrCast(&light),
            );
        }
    } else {
        // fill with black
    }
}

pub fn uploadBottomNorthWestOverlap(light_texture: LightTexture, neighbor_chunk_or_null: ?*Chunk) void {
    if (neighbor_chunk_or_null) |neighbor_chunk| {
        const light = neighbor_chunk.getLight(.{ .x = Chunk.EDGE, .y = Chunk.EDGE, .z = Chunk.EDGE });

        gl.TextureSubImage3D(
            light_texture.handle,
            0,
            0,
            0,
            0,
            1,
            1,
            1,
            gl.RGBA,
            gl.UNSIGNED_SHORT_4_4_4_4,
            @ptrCast(&light),
        );
    } else {
        // fill with black
    }
}

pub fn uploadTopNorthWestOverlap(light_texture: LightTexture, neighbor_chunk_or_null: ?*Chunk) void {
    if (neighbor_chunk_or_null) |neighbor_chunk| {
        const light = neighbor_chunk.getLight(.{ .x = Chunk.EDGE, .y = 0, .z = Chunk.EDGE });

        gl.TextureSubImage3D(
            light_texture.handle,
            0,
            0,
            Chunk.SIZE + 1,
            0,
            1,
            1,
            1,
            gl.RGBA,
            gl.UNSIGNED_SHORT_4_4_4_4,
            @ptrCast(&light),
        );
    } else {
        // fill with black
    }
}

pub fn uploadNorthEastOverlap(light_texture: LightTexture, neighbor_chunk_or_null: ?*Chunk) void {
    if (neighbor_chunk_or_null) |neighbor_chunk| {
        for (0..Chunk.SIZE) |y| {
            const light = neighbor_chunk.getLight(.{ .x = 0, .y = @intCast(y), .z = Chunk.EDGE });

            gl.TextureSubImage3D(
                light_texture.handle,
                0,
                Chunk.SIZE + 1,
                @intCast(y + 1),
                0,
                1,
                1,
                1,
                gl.RGBA,
                gl.UNSIGNED_SHORT_4_4_4_4,
                @ptrCast(&light),
            );
        }
    } else {
        // fill with black
    }
}

pub fn uploadBottomNorthEastOverlap(light_texture: LightTexture, neighbor_chunk_or_null: ?*Chunk) void {
    if (neighbor_chunk_or_null) |neighbor_chunk| {
        const light = neighbor_chunk.getLight(.{ .x = 0, .y = Chunk.EDGE, .z = Chunk.EDGE });

        gl.TextureSubImage3D(
            light_texture.handle,
            0,
            Chunk.SIZE + 1,
            0,
            0,
            1,
            1,
            1,
            gl.RGBA,
            gl.UNSIGNED_SHORT_4_4_4_4,
            @ptrCast(&light),
        );
    } else {
        // fill with black
    }
}

pub fn uploadTopNorthEastOverlap(light_texture: LightTexture, neighbor_chunk_or_null: ?*Chunk) void {
    if (neighbor_chunk_or_null) |neighbor_chunk| {
        const light = neighbor_chunk.getLight(.{ .x = 0, .y = 0, .z = Chunk.EDGE });

        gl.TextureSubImage3D(
            light_texture.handle,
            0,
            Chunk.SIZE + 1,
            Chunk.SIZE + 1,
            0,
            1,
            1,
            1,
            gl.RGBA,
            gl.UNSIGNED_SHORT_4_4_4_4,
            @ptrCast(&light),
        );
    } else {
        // fill with black
    }
}

pub fn uploadSouthWestOverlap(light_texture: LightTexture, neighbor_chunk_or_null: ?*Chunk) void {
    if (neighbor_chunk_or_null) |neighbor_chunk| {
        for (0..Chunk.SIZE) |y| {
            const light = neighbor_chunk.getLight(.{ .x = Chunk.EDGE, .y = @intCast(y), .z = 0 });

            gl.TextureSubImage3D(
                light_texture.handle,
                0,
                0,
                @intCast(y + 1),
                Chunk.SIZE + 1,
                1,
                1,
                1,
                gl.RGBA,
                gl.UNSIGNED_SHORT_4_4_4_4,
                @ptrCast(&light),
            );
        }
    } else {
        // fill with black
    }
}

pub fn uploadBottomSouthWestOverlap(light_texture: LightTexture, neighbor_chunk_or_null: ?*Chunk) void {
    if (neighbor_chunk_or_null) |neighbor_chunk| {
        const light = neighbor_chunk.getLight(.{ .x = Chunk.EDGE, .y = Chunk.EDGE, .z = 0 });

        gl.TextureSubImage3D(
            light_texture.handle,
            0,
            0,
            0,
            Chunk.SIZE + 1,
            1,
            1,
            1,
            gl.RGBA,
            gl.UNSIGNED_SHORT_4_4_4_4,
            @ptrCast(&light),
        );
    } else {
        // fill with black
    }
}

pub fn uploadTopSouthWestOverlap(light_texture: LightTexture, neighbor_chunk_or_null: ?*Chunk) void {
    if (neighbor_chunk_or_null) |neighbor_chunk| {
        const light = neighbor_chunk.getLight(.{ .x = Chunk.EDGE, .y = 0, .z = 0 });

        gl.TextureSubImage3D(
            light_texture.handle,
            0,
            0,
            Chunk.SIZE + 1,
            Chunk.SIZE + 1,
            1,
            1,
            1,
            gl.RGBA,
            gl.UNSIGNED_SHORT_4_4_4_4,
            @ptrCast(&light),
        );
    } else {
        // fill with black
    }
}

pub fn uploadSouthEastOverlap(light_texture: LightTexture, neighbor_chunk_or_null: ?*Chunk) void {
    if (neighbor_chunk_or_null) |neighbor_chunk| {
        for (0..Chunk.SIZE) |y| {
            const light = neighbor_chunk.getLight(.{ .x = 0, .y = @intCast(y), .z = 0 });

            gl.TextureSubImage3D(
                light_texture.handle,
                0,
                Chunk.SIZE + 1,
                @intCast(y + 1),
                Chunk.SIZE + 1,
                1,
                1,
                1,
                gl.RGBA,
                gl.UNSIGNED_SHORT_4_4_4_4,
                @ptrCast(&light),
            );
        }
    } else {
        // fill with black
    }
}

pub fn uploadBottomSouthEastOverlap(light_texture: LightTexture, neighbor_chunk_or_null: ?*Chunk) void {
    if (neighbor_chunk_or_null) |neighbor_chunk| {
        const light = neighbor_chunk.getLight(.{ .x = 0, .y = Chunk.EDGE, .z = 0 });

        gl.TextureSubImage3D(
            light_texture.handle,
            0,
            Chunk.SIZE + 1,
            0,
            Chunk.SIZE + 1,
            1,
            1,
            1,
            gl.RGBA,
            gl.UNSIGNED_SHORT_4_4_4_4,
            @ptrCast(&light),
        );
    } else {
        // fill with black
    }
}

pub fn uploadTopSouthEastOverlap(light_texture: LightTexture, neighbor_chunk_or_null: ?*Chunk) void {
    if (neighbor_chunk_or_null) |neighbor_chunk| {
        const light = neighbor_chunk.getLight(.{ .x = 0, .y = 0, .z = 0 });

        gl.TextureSubImage3D(
            light_texture.handle,
            0,
            Chunk.SIZE + 1,
            Chunk.SIZE + 1,
            Chunk.SIZE + 1,
            1,
            1,
            1,
            gl.RGBA,
            gl.UNSIGNED_SHORT_4_4_4_4,
            @ptrCast(&light),
        );
    } else {
        // fill with black
    }
}

pub fn uploadBottomOverlap(light_texture: LightTexture, neighbor_chunk_or_null: ?*Chunk) void {
    if (neighbor_chunk_or_null) |neighbor_chunk| {
        for (0..Chunk.SIZE) |z| {
            const local_pos: Chunk.LocalPos = .{ .x = 0, .y = Chunk.EDGE, .z = @intCast(z) };

            gl.TextureSubImage3D(
                light_texture.handle,
                0,
                1,
                0,
                @intCast(z + 1),
                Chunk.SIZE,
                1,
                1,
                gl.RGBA,
                gl.UNSIGNED_SHORT_4_4_4_4,
                @ptrCast(neighbor_chunk.light[local_pos.idx()..]),
            );
        }
    } else {
        // fill with black
    }
}

pub fn uploadTopOverlap(light_texture: LightTexture, neighbor_chunk_or_null: ?*Chunk) void {
    if (neighbor_chunk_or_null) |neighbor_chunk| {
        for (0..Chunk.SIZE) |z| {
            const local_pos: Chunk.LocalPos = .{ .x = 0, .y = 0, .z = @intCast(z) };

            gl.TextureSubImage3D(
                light_texture.handle,
                0,
                1,
                Chunk.SIZE + 1,
                @intCast(z + 1),
                Chunk.SIZE,
                1,
                1,
                gl.RGBA,
                gl.UNSIGNED_SHORT_4_4_4_4,
                @ptrCast(neighbor_chunk.light[local_pos.idx()..]),
            );
        }
    } else {
        // fill with black
    }
}
