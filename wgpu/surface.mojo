"""
wgpu.surface — Surface RAII wrapper for on-screen rendering.

A Surface represents a platform window surface (Wayland/X11) that wgpu can
render into.  The normal flow is:

    surface = instance.create_surface_wayland(display, wl_surface)
    surface.configure(adapter_handle, device_handle, width, height)
    # render loop:
    frame = surface.get_current_texture()  # returns SurfaceFrame
    # ... render to tex ...
    surface.present()
"""

from std.memory import ArcPointer
from wgpu._ffi.lib import WGPULib
from wgpu._ffi.types import (
    WGPUSurfaceHandle, WGPUInstanceHandle, WGPUAdapterHandle, WGPUDeviceHandle, WGPUTextureHandle,
    WGPUTextureUsage, WGPUSType, WGPUPresentMode, WGPUCompositeAlphaMode,
    WGPUSurfaceGetCurrentTextureStatus,
)
from wgpu._ffi.alloc_guard import AllocGuard
from wgpu._ffi.handles import SurfaceHandle as SurfaceHandleNewtype
from wgpu._ffi.structs import (
    WGPUChainedStruct, WGPUStringView,
    WGPUSurfaceDescriptor, WGPUSurfaceCapabilities, WGPUSurfaceConfiguration,
    WGPUSurfaceTexture,
    WGPUSurfaceSourceWaylandSurface, WGPUSurfaceSourceXlibWindow,
)


@fieldwise_init
struct SurfaceFrame(TrivialRegisterPassable):
    """Return value from Surface.get_current_texture().

    Use is_renderable() to check whether the frame is safe to draw into.
    A suboptimal frame is still renderable, but a resize is recommended.
    """
    var texture: WGPUTextureHandle
    var status:  UInt32

    def is_renderable(self) -> Bool:
        """True when the frame can be rendered to (optimal or suboptimal)."""
        return (
            self.status == WGPUSurfaceGetCurrentTextureStatus.SuccessOptimal or
            self.status == WGPUSurfaceGetCurrentTextureStatus.SuccessSuboptimal
        )

    def is_optimal(self) -> Bool:
        """True when the swapchain is in the ideal state."""
        return self.status == WGPUSurfaceGetCurrentTextureStatus.SuccessOptimal

    def is_suboptimal(self) -> Bool:
        """True when renderable but a surface resize / reconfigure is recommended."""
        return self.status == WGPUSurfaceGetCurrentTextureStatus.SuccessSuboptimal

    def is_lost(self) -> Bool:
        """True when the surface is lost and must be reconfigured before rendering."""
        return self.status == WGPUSurfaceGetCurrentTextureStatus.Lost


struct Surface(Movable):
    """RAII wrapper around a WGPUSurface for on-screen rendering."""

    var _lib:    ArcPointer[WGPULib]
    var _handle: WGPUSurfaceHandle
    var _format: UInt32   # texture format chosen during configure()
    var _width:  UInt32
    var _height: UInt32

    def __init__(out self, lib: ArcPointer[WGPULib], handle: WGPUSurfaceHandle):
        self._lib    = lib
        self._handle = handle
        self._format = 0
        self._width  = 0
        self._height = 0

    def __init__(out self, *, deinit take: Self):
        self._lib    = take._lib^
        self._handle = take._handle
        self._format = take._format
        self._width  = take._width
        self._height = take._height

    def __del__(deinit self):
        if Int(self._handle) != 0:
            self._lib[].surface_unconfigure(self._handle)
        self._lib[].surface_release(self._handle)

    # ------------------------------------------------------------------
    # Properties
    # ------------------------------------------------------------------

    def handle(self) -> SurfaceHandleNewtype:
        return SurfaceHandleNewtype(self._handle)

    def format(self) -> UInt32:
        """Texture format chosen during configure()."""
        return self._format

    def width(self) -> UInt32:
        return self._width

    def height(self) -> UInt32:
        return self._height

    # ------------------------------------------------------------------
    # Configure — query caps, pick format, call wgpuSurfaceConfigure
    # ------------------------------------------------------------------

    def configure(
        mut self,
        adapter: WGPUAdapterHandle,
        device: WGPUDeviceHandle,
        width: UInt32,
        height: UInt32,
        present_mode: UInt32 = WGPUPresentMode.Fifo,
    ):
        """Configure the swap chain. Must be called before get_current_texture()."""
        # Query supported formats; use first (preferred) or fall back to Bgra8Unorm.
        var fmt: UInt32 = 0x1B  # Bgra8Unorm fallback
        with AllocGuard[WGPUSurfaceCapabilities](1) as caps_p:
            caps_p[] = WGPUSurfaceCapabilities(
                OpaquePointer[MutExternalOrigin](unsafe_from_address=0), UInt64(0),
                UInt(0), UnsafePointer[UInt32, MutExternalOrigin](unsafe_from_address=0),
                UInt(0), UnsafePointer[UInt32, MutExternalOrigin](unsafe_from_address=0),
                UInt(0), UnsafePointer[UInt32, MutExternalOrigin](unsafe_from_address=0),
            )
            _ = self._lib[].surface_get_capabilities(self._handle, adapter, caps_p)
            if caps_p[].format_count > 0:
                fmt = caps_p[].formats[0]
            self._lib[].surface_capabilities_free(caps_p)

        self._format = fmt
        self._width  = width
        self._height = height

        with AllocGuard[WGPUSurfaceConfiguration](1) as config_p:
            config_p[] = WGPUSurfaceConfiguration(
                OpaquePointer[MutExternalOrigin](unsafe_from_address=0),
                device,
                fmt,
                WGPUTextureUsage.RENDER_ATTACHMENT.value,
                width,
                height,
                UInt(0),
                UnsafePointer[UInt32, MutExternalOrigin](unsafe_from_address=0),
                WGPUCompositeAlphaMode.Auto,
                present_mode,
            )
            self._lib[].surface_configure(self._handle, config_p)

    # ------------------------------------------------------------------
    # Per-frame operations
    # ------------------------------------------------------------------

    def get_current_texture(self) -> SurfaceFrame:
        """Acquire the next swapchain texture.

        Returns a SurfaceFrame. Render only when status == 1 or 2.
        """
        with AllocGuard[WGPUSurfaceTexture](1) as st_p:
            st_p[] = WGPUSurfaceTexture(
                OpaquePointer[MutExternalOrigin](unsafe_from_address=0),
                WGPUTextureHandle(unsafe_from_address=0),
                UInt32(0),
            )
            self._lib[].surface_get_current_texture(self._handle, st_p)
            return SurfaceFrame(st_p[].texture, st_p[].status)

    def present(self):
        """Present the rendered frame."""
        self._lib[].surface_present(self._handle)

# ------------------------------------------------------------------
# Factory functions — platform-specific surface creation
# (Free functions because static methods on parameterized structs
#  can't infer the struct's implicit parameters.)
# ------------------------------------------------------------------

def create_surface_wayland(
    lib: ArcPointer[WGPULib],
    inst: WGPUInstanceHandle,
    display: OpaquePointer[MutExternalOrigin],
    wayland_surface: OpaquePointer[MutExternalOrigin],
) raises -> Surface:
    """Create a surface from a Wayland display and wl_surface pointer."""
    var src_guard = AllocGuard[WGPUSurfaceSourceWaylandSurface](1)
    src_guard.ptr()[] = WGPUSurfaceSourceWaylandSurface(
        WGPUChainedStruct(OpaquePointer[MutExternalOrigin](unsafe_from_address=0), WGPUSType.SurfaceSourceWaylandSurface),
        display,
        wayland_surface,
    )
    var desc_guard = AllocGuard[WGPUSurfaceDescriptor](1)
    desc_guard.ptr()[] = WGPUSurfaceDescriptor(
        src_guard.ptr().bitcast[NoneType](),
        WGPUStringView.null_view(),
    )
    var h = lib[].instance_create_surface(inst, desc_guard.ptr())
    if h == OpaquePointer[MutExternalOrigin](unsafe_from_address=0):
        raise Error("wgpuInstanceCreateSurface returned null (Wayland)")
    return Surface(lib, h)

def create_surface_xlib(
    lib: ArcPointer[WGPULib],
    inst: WGPUInstanceHandle,
    display: OpaquePointer[MutExternalOrigin],
    window: UInt64,
) raises -> Surface:
    """Create a surface from an X11 Display* and Window id."""
    var src_guard = AllocGuard[WGPUSurfaceSourceXlibWindow](1)
    src_guard.ptr()[] = WGPUSurfaceSourceXlibWindow(
        WGPUChainedStruct(OpaquePointer[MutExternalOrigin](unsafe_from_address=0), WGPUSType.SurfaceSourceXlibWindow),
        display,
        window,
    )
    var desc_guard = AllocGuard[WGPUSurfaceDescriptor](1)
    desc_guard.ptr()[] = WGPUSurfaceDescriptor(
        src_guard.ptr().bitcast[NoneType](),
        WGPUStringView.null_view(),
    )
    var h = lib[].instance_create_surface(inst, desc_guard.ptr())
    if h == OpaquePointer[MutExternalOrigin](unsafe_from_address=0):
        raise Error("wgpuInstanceCreateSurface returned null (X11)")
    return Surface(lib, h)
