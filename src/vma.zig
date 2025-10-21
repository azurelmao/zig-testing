const std = @import("std");
const c = @import("vma");

fn vkResultToString(result: c.VkResult) [:0]const u8 {
    return switch (result) {
        c.VK_SUCCESS => "VK_SUCCESS",
        c.VK_NOT_READY => "VK_NOT_READY",
        c.VK_TIMEOUT => "VK_TIMEOUT",
        c.VK_EVENT_SET => "VK_EVENT_SET",
        c.VK_EVENT_RESET => "VK_EVENT_RESET",
        c.VK_INCOMPLETE => "VK_INCOMPLETE",
        c.VK_ERROR_OUT_OF_HOST_MEMORY => "VK_ERROR_OUT_OF_HOST_MEMORY",
        c.VK_ERROR_OUT_OF_DEVICE_MEMORY => "VK_ERROR_OUT_OF_DEVICE_MEMORY",
        c.VK_ERROR_INITIALIZATION_FAILED => "VK_ERROR_INITIALIZATION_FAILED",
        c.VK_ERROR_DEVICE_LOST => "VK_ERROR_DEVICE_LOST",
        c.VK_ERROR_MEMORY_MAP_FAILED => "VK_ERROR_MEMORY_MAP_FAILED",
        c.VK_ERROR_LAYER_NOT_PRESENT => "VK_ERROR_LAYER_NOT_PRESENT",
        c.VK_ERROR_EXTENSION_NOT_PRESENT => "VK_ERROR_EXTENSION_NOT_PRESENT",
        c.VK_ERROR_FEATURE_NOT_PRESENT => "VK_ERROR_FEATURE_NOT_PRESENT",
        c.VK_ERROR_INCOMPATIBLE_DRIVER => "VK_ERROR_INCOMPATIBLE_DRIVER",
        c.VK_ERROR_TOO_MANY_OBJECTS => "VK_ERROR_TOO_MANY_OBJECTS",
        c.VK_ERROR_FORMAT_NOT_SUPPORTED => "VK_ERROR_FORMAT_NOT_SUPPORTED",
        c.VK_ERROR_FRAGMENTED_POOL => "VK_ERROR_FRAGMENTED_POOL",
        c.VK_ERROR_UNKNOWN => "VK_ERROR_UNKNOWN",
        c.VK_ERROR_OUT_OF_POOL_MEMORY => "VK_ERROR_OUT_OF_POOL_MEMORY",
        c.VK_ERROR_INVALID_EXTERNAL_HANDLE => "VK_ERROR_INVALID_EXTERNAL_HANDLE",
        c.VK_ERROR_FRAGMENTATION => "VK_ERROR_FRAGMENTATION",
        c.VK_ERROR_INVALID_OPAQUE_CAPTURE_ADDRESS => "VK_ERROR_INVALID_OPAQUE_CAPTURE_ADDRESS",
        c.VK_PIPELINE_COMPILE_REQUIRED => "VK_PIPELINE_COMPILE_REQUIRED",
        c.VK_ERROR_SURFACE_LOST_KHR => "VK_ERROR_SURFACE_LOST_KHR",
        c.VK_ERROR_NATIVE_WINDOW_IN_USE_KHR => "VK_ERROR_NATIVE_WINDOW_IN_USE_KHR",
        c.VK_SUBOPTIMAL_KHR => "VK_SUBOPTIMAL_KHR",
        c.VK_ERROR_OUT_OF_DATE_KHR => "VK_ERROR_OUT_OF_DATE_KHR",
        c.VK_ERROR_INCOMPATIBLE_DISPLAY_KHR => "VK_ERROR_INCOMPATIBLE_DISPLAY_KHR",
        c.VK_ERROR_VALIDATION_FAILED_EXT => "VK_ERROR_VALIDATION_FAILED_EXT",
        c.VK_ERROR_INVALID_SHADER_NV => "VK_ERROR_INVALID_SHADER_NV",
        c.VK_ERROR_IMAGE_USAGE_NOT_SUPPORTED_KHR => "VK_ERROR_IMAGE_USAGE_NOT_SUPPORTED_KHR",
        c.VK_ERROR_VIDEO_PICTURE_LAYOUT_NOT_SUPPORTED_KHR => "VK_ERROR_VIDEO_PICTURE_LAYOUT_NOT_SUPPORTED_KHR",
        c.VK_ERROR_VIDEO_PROFILE_OPERATION_NOT_SUPPORTED_KHR => "VK_ERROR_VIDEO_PROFILE_OPERATION_NOT_SUPPORTED_KHR",
        c.VK_ERROR_VIDEO_PROFILE_FORMAT_NOT_SUPPORTED_KHR => "VK_ERROR_VIDEO_PROFILE_FORMAT_NOT_SUPPORTED_KHR",
        c.VK_ERROR_VIDEO_PROFILE_CODEC_NOT_SUPPORTED_KHR => "VK_ERROR_VIDEO_PROFILE_CODEC_NOT_SUPPORTED_KHR",
        c.VK_ERROR_VIDEO_STD_VERSION_NOT_SUPPORTED_KHR => "VK_ERROR_VIDEO_STD_VERSION_NOT_SUPPORTED_KHR",
        c.VK_ERROR_INVALID_DRM_FORMAT_MODIFIER_PLANE_LAYOUT_EXT => "VK_ERROR_INVALID_DRM_FORMAT_MODIFIER_PLANE_LAYOUT_EXT",
        c.VK_ERROR_NOT_PERMITTED_KHR => "VK_ERROR_NOT_PERMITTED_KHR",
        c.VK_ERROR_FULL_SCREEN_EXCLUSIVE_MODE_LOST_EXT => "VK_ERROR_FULL_SCREEN_EXCLUSIVE_MODE_LOST_EXT",
        c.VK_THREAD_IDLE_KHR => "VK_THREAD_IDLE_KHR",
        c.VK_THREAD_DONE_KHR => "VK_THREAD_DONE_KHR",
        c.VK_OPERATION_DEFERRED_KHR => "VK_OPERATION_DEFERRED_KHR",
        c.VK_OPERATION_NOT_DEFERRED_KHR => "VK_OPERATION_NOT_DEFERRED_KHR",
        // c.VK_ERROR_INVALID_VIDEO_STD_PARAMETERS_KHR => "VK_ERROR_INVALID_VIDEO_STD_PARAMETERS_KHR",
        c.VK_ERROR_COMPRESSION_EXHAUSTED_EXT => "VK_ERROR_COMPRESSION_EXHAUSTED_EXT",
        // c.VK_ERROR_INCOMPATIBLE_SHADER_BINARY_EXT => "VK_ERROR_INCOMPATIBLE_SHADER_BINARY_EXT",
        else => unreachable,
    };
}

pub const VirtualAllocation = struct {
    handle: c.VmaVirtualAllocation,
};

pub const VirtualBlock = struct {
    block: c.VmaVirtualBlock,

    pub fn init(info: c.VmaVirtualBlockCreateInfo) !VirtualBlock {
        var block: c.VmaVirtualBlock = undefined;

        const result = c.vmaCreateVirtualBlock(&info, &block);
        if (result != c.VK_SUCCESS) {
            std.log.err("{s}", .{vkResultToString(result)});
            return error.VmaCreateVirtualBlockFailed;
        }

        return .{
            .block = block,
        };
    }

    pub fn deinit(self: VirtualBlock) void {
        c.vmaDestroyVirtualBlock(self.block);
    }

    pub fn alloc(self: VirtualBlock, info: c.VmaVirtualAllocationCreateInfo) !VirtualAllocation {
        var handle: c.VmaVirtualAllocation = undefined;
        var offset: c.VkDeviceSize = undefined;

        const result = c.vmaVirtualAllocate(self.block, &info, &handle, &offset);
        if (result != c.VK_SUCCESS) {
            std.log.err("{s}", .{vkResultToString(result)});
            return error.VmaVirtualAllocateFailed;
        }

        return .{
            .handle = handle,
        };
    }

    pub fn allocInfo(self: VirtualBlock, allocation: VirtualAllocation) c.VmaVirtualAllocationInfo {
        var info: c.VmaVirtualAllocationInfo = undefined;
        c.vmaGetVirtualAllocationInfo(self.block, allocation.handle, &info);
        return info;
    }

    pub fn free(self: VirtualBlock, allocation: VirtualAllocation) void {
        c.vmaVirtualFree(self.block, allocation.handle);
    }
};
