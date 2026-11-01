"""wgpu._backend.wgpu_native.web_structs — structs only emdawnwebgpu's webgpu.h has.

Checked against that header by `pixi run check-web-struct-layout`.
"""

from wgpu._backend.wgpu_native.structs import WGPUChainedStruct, WGPUStringView

# WGPUSType_EmscriptenSurfaceSourceCanvasHTMLSelector
comptime WGPU_STYPE_EMSCRIPTEN_SURFACE_SOURCE_CANVAS_HTML_SELECTOR: UInt32 = 0x00040000


@fieldwise_init
struct WGPUEmscriptenSurfaceSourceCanvasHTMLSelector(TrivialRegisterPassable):
    var chain: WGPUChainedStruct
    var selector: WGPUStringView
