const std = @import("std");
const c = @import("vma");

pub const Error = error{
    Success,
    NotReady,
    Timeout,
    EventSet,
    EventReset,
    Incomplete,
    ErrorOutOfHostMemory,
    ErrorOutOfDeviceMemory,
    ErrorInitializationFailed,
    ErrorDeviceLost,
    ErrorMemoryMapFailed,
    ErrorLayerNotPresent,
    ErrorExtensionNotPresent,
    ErrorFeatureNotPresent,
    ErrorIncompatibleDriver,
    ErrorTooManyObjects,
    ErrorFormatNotSupported,
    ErrorFragmentedPool,
    ErrorUnknown,
    ErrorOutOfPoolMemory,
    ErrorInvalidExternalHandle,
    ErrorFragmentation,
    ErrorInvalidOpaqueCaptureAddress,
    PipelineCompileRequired,
    ErrorSurfaceLostKhr,
    ErrorNativeWindowInUseKhr,
    SuboptimalKhr,
    ErrorOutOfDateKhr,
    ErrorIncompatibleDisplayKhr,
    ErrorValidationFailedExt,
    ErrorInvalidShaderNv,
    ErrorImageUsageNotSupportedKhr,
    ErrorVideoPictureLayoutNotSupportedKhr,
    ErrorVideoProfileOperationNotSupportedKhr,
    ErrorVideoProfileFormatNotSupportedKhr,
    ErrorVideoProfileCodecNotSupportedKhr,
    ErrorVideoStdVersionNotSupportedKhr,
    ErrorInvalidDrmFormatModifierPlaneLayoutExt,
    ErrorNotPermittedKhr,
    ErrorFullScreenExclusiveModeLostExt,
    ThreadIdleKhr,
    ThreadDoneKhr,
    OperationDeferredKhr,
    OperationNotDeferredKhr,
    ErrorCompressionExhaustedExt,
};

pub fn vkResultToError(result: c.VkResult) Error {
    return switch (result) {
        c.VK_SUCCESS => Error.Success,
        c.VK_NOT_READY => Error.NotReady,
        c.VK_TIMEOUT => Error.Timeout,
        c.VK_EVENT_SET => Error.EventSet,
        c.VK_EVENT_RESET => Error.EventReset,
        c.VK_INCOMPLETE => Error.Incomplete,
        c.VK_ERROR_OUT_OF_HOST_MEMORY => Error.ErrorOutOfHostMemory,
        c.VK_ERROR_OUT_OF_DEVICE_MEMORY => Error.ErrorOutOfDeviceMemory,
        c.VK_ERROR_INITIALIZATION_FAILED => Error.ErrorInitializationFailed,
        c.VK_ERROR_DEVICE_LOST => Error.ErrorDeviceLost,
        c.VK_ERROR_MEMORY_MAP_FAILED => Error.ErrorMemoryMapFailed,
        c.VK_ERROR_LAYER_NOT_PRESENT => Error.ErrorLayerNotPresent,
        c.VK_ERROR_EXTENSION_NOT_PRESENT => Error.ErrorExtensionNotPresent,
        c.VK_ERROR_FEATURE_NOT_PRESENT => Error.ErrorFeatureNotPresent,
        c.VK_ERROR_INCOMPATIBLE_DRIVER => Error.ErrorIncompatibleDriver,
        c.VK_ERROR_TOO_MANY_OBJECTS => Error.ErrorTooManyObjects,
        c.VK_ERROR_FORMAT_NOT_SUPPORTED => Error.ErrorFormatNotSupported,
        c.VK_ERROR_FRAGMENTED_POOL => Error.ErrorFragmentedPool,
        c.VK_ERROR_UNKNOWN => Error.ErrorUnknown,
        c.VK_ERROR_OUT_OF_POOL_MEMORY => Error.ErrorOutOfPoolMemory,
        c.VK_ERROR_INVALID_EXTERNAL_HANDLE => Error.ErrorInvalidExternalHandle,
        c.VK_ERROR_FRAGMENTATION => Error.ErrorFragmentation,
        c.VK_ERROR_INVALID_OPAQUE_CAPTURE_ADDRESS => Error.ErrorInvalidOpaqueCaptureAddress,
        c.VK_PIPELINE_COMPILE_REQUIRED => Error.PipelineCompileRequired,
        c.VK_ERROR_SURFACE_LOST_KHR => Error.ErrorSurfaceLostKhr,
        c.VK_ERROR_NATIVE_WINDOW_IN_USE_KHR => Error.ErrorNativeWindowInUseKhr,
        c.VK_SUBOPTIMAL_KHR => Error.SuboptimalKhr,
        c.VK_ERROR_OUT_OF_DATE_KHR => Error.ErrorOutOfDateKhr,
        c.VK_ERROR_INCOMPATIBLE_DISPLAY_KHR => Error.ErrorIncompatibleDisplayKhr,
        c.VK_ERROR_VALIDATION_FAILED_EXT => Error.ErrorValidationFailedExt,
        c.VK_ERROR_INVALID_SHADER_NV => Error.ErrorInvalidShaderNv,
        c.VK_ERROR_IMAGE_USAGE_NOT_SUPPORTED_KHR => Error.ErrorImageUsageNotSupportedKhr,
        c.VK_ERROR_VIDEO_PICTURE_LAYOUT_NOT_SUPPORTED_KHR => Error.ErrorVideoPictureLayoutNotSupportedKhr,
        c.VK_ERROR_VIDEO_PROFILE_OPERATION_NOT_SUPPORTED_KHR => Error.ErrorVideoProfileOperationNotSupportedKhr,
        c.VK_ERROR_VIDEO_PROFILE_FORMAT_NOT_SUPPORTED_KHR => Error.ErrorVideoProfileFormatNotSupportedKhr,
        c.VK_ERROR_VIDEO_PROFILE_CODEC_NOT_SUPPORTED_KHR => Error.ErrorVideoProfileCodecNotSupportedKhr,
        c.VK_ERROR_VIDEO_STD_VERSION_NOT_SUPPORTED_KHR => Error.ErrorVideoStdVersionNotSupportedKhr,
        c.VK_ERROR_INVALID_DRM_FORMAT_MODIFIER_PLANE_LAYOUT_EXT => Error.ErrorInvalidDrmFormatModifierPlaneLayoutExt,
        c.VK_ERROR_NOT_PERMITTED_KHR => Error.ErrorNotPermittedKhr,
        c.VK_ERROR_FULL_SCREEN_EXCLUSIVE_MODE_LOST_EXT => Error.ErrorFullScreenExclusiveModeLostExt,
        c.VK_THREAD_IDLE_KHR => Error.ThreadIdleKhr,
        c.VK_THREAD_DONE_KHR => Error.ThreadDoneKhr,
        c.VK_OPERATION_DEFERRED_KHR => Error.OperationDeferredKhr,
        c.VK_OPERATION_NOT_DEFERRED_KHR => Error.OperationNotDeferredKhr,
        c.VK_ERROR_COMPRESSION_EXHAUSTED_EXT => Error.ErrorCompressionExhaustedExt,
        else => unreachable,
    };
}

pub const VirtualAllocation = struct {
    handle: c.VmaVirtualAllocation,
};

pub const VirtualBlock = struct {
    handle: c.VmaVirtualBlock,

    pub fn init(info: c.VmaVirtualBlockCreateInfo) VirtualBlock {
        var handle: c.VmaVirtualBlock = undefined;

        const result = c.vmaCreateVirtualBlock(&info, &handle);
        if (result != c.VK_SUCCESS) {
            std.debug.panic("{s}", .{@errorName(vkResultToError(result))});
        }

        return .{
            .handle = handle,
        };
    }

    pub fn deinit(self: VirtualBlock) void {
        c.vmaClearVirtualBlock(self.handle);
        c.vmaDestroyVirtualBlock(self.handle);
    }

    pub fn alloc(self: VirtualBlock, info: c.VmaVirtualAllocationCreateInfo) !VirtualAllocation {
        var handle: c.VmaVirtualAllocation = undefined;

        std.debug.assert(info.size != 0);

        const result = c.vmaVirtualAllocate(self.handle, &info, &handle, null);
        if (result != c.VK_SUCCESS) {
            return vkResultToError(result);
        }

        return .{
            .handle = handle,
        };
    }

    pub fn allocInfo(self: VirtualBlock, allocation: VirtualAllocation) c.VmaVirtualAllocationInfo {
        var info: c.VmaVirtualAllocationInfo = undefined;
        c.vmaGetVirtualAllocationInfo(self.handle, allocation.handle, &info);
        return info;
    }

    pub fn free(self: VirtualBlock, allocation: VirtualAllocation) void {
        c.vmaVirtualFree(self.handle, allocation.handle);
    }
};
