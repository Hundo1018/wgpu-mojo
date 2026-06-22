"""
wgpu.shader — ShaderModule RAII wrapper.
"""

from std.memory import ArcPointer
from wgpu._ffi.lib import WGPULib
from wgpu._ffi.nulls import null_opaque
from wgpu._ffi.types import WGPUDeviceHandle, WGPUShaderModuleHandle, WGPUInstanceHandle, WGPUCallbackMode
from wgpu._ffi.structs import WGPUStringView, WGPUCompilationInfoCallbackInfo, WGPUCompilationInfo, WGPUCompilationMessage, str_to_sv
from wgpu._ffi.handles import ShaderModuleHandle
from wgpu._backend.wgpu_native.loader import _CompilationResult
from wgpu._ffi.alloc_guard import AllocGuard


struct ShaderModule(Movable, Boolable):
    """RAII wrapper around a WGPUShaderModule."""

    var _lib:      ArcPointer[WGPULib]
    var _handle:   WGPUShaderModuleHandle
    var _instance: WGPUInstanceHandle

    def __init__(
        out self,
        lib: ArcPointer[WGPULib],
        handle: WGPUShaderModuleHandle,
        instance: WGPUInstanceHandle,
    ):
        self._lib      = lib
        self._handle   = handle
        self._instance = instance

    def __init__(out self, *, deinit take: Self):
        self._lib      = take._lib^
        self._handle   = take._handle
        self._instance = take._instance

    def __del__(deinit self):
        self._lib[].shader_module_release(self._handle)

    def handle(self) -> ShaderModuleHandle:
        return ShaderModuleHandle(self._handle)

    def __bool__(self) -> Bool:
        return Int(self._handle) != 0

    def set_label(self, label: String):
        var sv = str_to_sv(label) if label.byte_length() > 0 else WGPUStringView.null_view()
        self._lib[].shader_module_set_label(self._handle, sv)

    def get_compilation_info(self) raises -> List[String]:
        """Return compiler messages for this shader module.

        Returns a list of strings formatted as "Error|Warning|Info line:col: message".
        Empty list means no messages (shader compiled cleanly).
        Raises if wgpu reports a status other than Success.
        """
        with AllocGuard[_CompilationResult](1) as result:
            result[] = _CompilationResult(UInt32(0), null_opaque())
            with AllocGuard[WGPUCompilationInfoCallbackInfo](1) as cb_info_p:
                cb_info_p[] = WGPUCompilationInfoCallbackInfo(
                    null_opaque(),
                    WGPUCallbackMode.AllowSpontaneous,
                    self._lib[]._compilation_info_cb_ptr,
                    result.bitcast[NoneType](),
                    null_opaque(),
                )
                self._lib[].shader_module_get_compilation_info(self._handle, cb_info_p)
            self._lib[].instance_process_events(self._instance)

            var status = result[].status
            if status != UInt32(1):  # WGPUCompilationInfoRequestStatus.Success == 1
                raise Error("get_compilation_info failed, status=" + String(status))

            var info_ptr = result[].info.bitcast[WGPUCompilationInfo]()
            var msg_count = info_ptr[].message_count
            var messages = List[String]()
            for i in range(Int(msg_count)):
                var kind = String("Unknown")
                var msg_type = info_ptr[].messages[i].type
                if msg_type == UInt32(1):
                    kind = "Error"
                elif msg_type == UInt32(2):
                    kind = "Warning"
                elif msg_type == UInt32(3):
                    kind = "Info"
                var p = info_ptr[].messages[i].message.data.bitcast[UInt8]()
                var n = info_ptr[].messages[i].message.length
                var line = info_ptr[].messages[i].line_num
                var col  = info_ptr[].messages[i].line_pos
                var text = String()
                var j = UInt(0)
                while j < n and p[Int(j)] != 0:
                    text += chr(Int(p[Int(j)]))
                    j += 1
                messages.append(
                    kind + " " + String(line) + ":" + String(col) + ": " + text
                )
            return messages^
