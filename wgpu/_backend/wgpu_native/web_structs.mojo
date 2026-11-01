"""wgpu._backend.wgpu_native.web_structs — structs only the web target has.

Not in any header: the browser translation layer defines the SType and reads
this chain. Layout is checked by hand against web/webgpu_layout.json (#17).
"""

from wgpu._backend.wgpu_native.structs import WGPUChainedStruct, WGPUStringView

# WGPUSType_SurfaceSourceCanvasHTMLSelector (wgpu-mojo's own, outside the
# standard and wgpu-native ranges)
comptime WGPU_STYPE_SURFACE_SOURCE_CANVAS_HTML_SELECTOR: UInt32 = 0x00050000


@fieldwise_init
struct WGPUSurfaceSourceCanvasHTMLSelector(TrivialRegisterPassable):
    var chain: WGPUChainedStruct
    var selector: WGPUStringView
