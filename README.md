Requires zig version `0.14.1`

Then do `zig build` and execute `./zig-out/bin/testing` in the project dir

TODOs:
- generate draw commands every time the world mesh changes, and only for chunk meshes which haven't been culled