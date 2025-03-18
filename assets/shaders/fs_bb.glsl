#version 460 core

layout (early_fragment_tests) in;

struct DrawArraysIndirectCommand {
    uint count;
    uint instance_count;
    uint first_vertex;
    uint base_instance;
};

layout(binding = 6, std430) buffer ssbo6 {
    DrawArraysIndirectCommand sSolidDrawCommands[];
};

layout(binding = 7, std430) buffer ssbo7 {
    DrawArraysIndirectCommand sWaterDrawCommands[];
};

layout(binding = 8, std430) buffer ssbo8 {
    DrawArraysIndirectCommand sIceDrawCommands[];
};

layout(binding = 9, std430) buffer ssbo9 {
    DrawArraysIndirectCommand sGlassStainedDrawCommands[];
};

layout(binding = 10, std430) buffer ssbo10 {
    DrawArraysIndirectCommand sGlassDrawCommands[];
};

flat in uint pDrawCommandId;

void main() {
    sSolidDrawCommands[pDrawCommandId].instance_count = sSolidDrawCommands[pDrawCommandId].base_instance;
    sWaterDrawCommands[pDrawCommandId].instance_count = sWaterDrawCommands[pDrawCommandId].base_instance;
    sIceDrawCommands[pDrawCommandId].instance_count = sIceDrawCommands[pDrawCommandId].base_instance;
    sGlassStainedDrawCommands[pDrawCommandId].instance_count = sGlassStainedDrawCommands[pDrawCommandId].base_instance;
    sGlassDrawCommands[pDrawCommandId].instance_count = sGlassDrawCommands[pDrawCommandId].base_instance;

    sSolidDrawCommands[pDrawCommandId + 1].instance_count = sSolidDrawCommands[pDrawCommandId + 1].base_instance;
    sWaterDrawCommands[pDrawCommandId + 1].instance_count = sWaterDrawCommands[pDrawCommandId + 1].base_instance;
    sIceDrawCommands[pDrawCommandId + 1].instance_count = sIceDrawCommands[pDrawCommandId + 1].base_instance;
    sGlassStainedDrawCommands[pDrawCommandId + 1].instance_count = sGlassStainedDrawCommands[pDrawCommandId + 1].base_instance;
    sGlassDrawCommands[pDrawCommandId + 1].instance_count = sGlassDrawCommands[pDrawCommandId + 1].base_instance;

    sSolidDrawCommands[pDrawCommandId + 2].instance_count = sSolidDrawCommands[pDrawCommandId + 2].base_instance;
    sWaterDrawCommands[pDrawCommandId + 2].instance_count = sWaterDrawCommands[pDrawCommandId + 2].base_instance;
    sIceDrawCommands[pDrawCommandId + 2].instance_count = sIceDrawCommands[pDrawCommandId + 2].base_instance;
    sGlassStainedDrawCommands[pDrawCommandId + 2].instance_count = sGlassStainedDrawCommands[pDrawCommandId + 2].base_instance;
    sGlassDrawCommands[pDrawCommandId + 2].instance_count = sGlassDrawCommands[pDrawCommandId + 2].base_instance;

    sSolidDrawCommands[pDrawCommandId + 3].instance_count = sSolidDrawCommands[pDrawCommandId + 3].base_instance;
    sWaterDrawCommands[pDrawCommandId + 3].instance_count = sWaterDrawCommands[pDrawCommandId + 3].base_instance;
    sIceDrawCommands[pDrawCommandId + 3].instance_count = sIceDrawCommands[pDrawCommandId + 3].base_instance;
    sGlassStainedDrawCommands[pDrawCommandId + 3].instance_count = sGlassStainedDrawCommands[pDrawCommandId + 3].base_instance;
    sGlassDrawCommands[pDrawCommandId + 3].instance_count = sGlassDrawCommands[pDrawCommandId + 3].base_instance;

    sSolidDrawCommands[pDrawCommandId + 4].instance_count = sSolidDrawCommands[pDrawCommandId + 4].base_instance;
    sWaterDrawCommands[pDrawCommandId + 4].instance_count = sWaterDrawCommands[pDrawCommandId + 4].base_instance;
    sIceDrawCommands[pDrawCommandId + 4].instance_count = sIceDrawCommands[pDrawCommandId + 4].base_instance;
    sGlassStainedDrawCommands[pDrawCommandId + 4].instance_count = sGlassStainedDrawCommands[pDrawCommandId + 4].base_instance;
    sGlassDrawCommands[pDrawCommandId + 4].instance_count = sGlassDrawCommands[pDrawCommandId + 4].base_instance;

    sSolidDrawCommands[pDrawCommandId + 5].instance_count = sSolidDrawCommands[pDrawCommandId + 5].base_instance;
    sWaterDrawCommands[pDrawCommandId + 5].instance_count = sWaterDrawCommands[pDrawCommandId + 5].base_instance;
    sIceDrawCommands[pDrawCommandId + 5].instance_count = sIceDrawCommands[pDrawCommandId + 5].base_instance;
    sGlassStainedDrawCommands[pDrawCommandId + 5].instance_count = sGlassStainedDrawCommands[pDrawCommandId + 5].base_instance;
    sGlassDrawCommands[pDrawCommandId + 5].instance_count = sGlassDrawCommands[pDrawCommandId + 5].base_instance;
}