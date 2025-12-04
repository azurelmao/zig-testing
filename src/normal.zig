const RaycastSide = @import("World.zig").RaycastSide;

pub const Normal = enum {
    west, // -x
    east, // +x
    bottom, // -y
    top, // +y
    north, // -z
    south, // +z,
    neither,

    pub fn toRaycastSide(self: Normal) RaycastSide {
        switch (self) {
            .west, .east, .bottom, .top, .north, .south => return @enumFromInt(@intFromEnum(self)),
            .neither => return .inside,
        }
    }
};
