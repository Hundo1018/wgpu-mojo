"""
GPU-compute fire simulation.

Demonstrates a full wgpu-mojo compute → render pipeline:
  1. A Doom-style cellular automaton runs each frame inside a WGSL
     compute shader over two ping-pong storage buffers.
  2. A render pass samples the result buffer and draws a fullscreen quad
     with a Mojo-branded orange-gold fire palette.

GPU architecture::

    Mojo CPU (orchestration)
      → queue_write_data()     # initial cold state
      → per-frame:
          WGSL compute pass    # fire physics → storage buffer (ping-pong)
          WGSL render  pass    # storage buffer → swapchain

Ecosystem note:
    The physics here runs via WebGPU compute shaders (WGSL).  Mojo's
    native GPU programming (std.gpu / DeviceContext) targets CUDA/ROCm and
    is under active integration in wgpu/_core/mojo_gpu/.  Once that bridge
    ships, Mojo-native GPU kernels will write directly into wgpu storage
    buffers — unifying HPC compute and interactive GPU graphics in a single
    Mojo program.

Run:
    pixi run example-fire-sim
"""

from wgpu import (
    Instance,
    WGPUBufferUsage, WGPUShaderStage, WGPU_WHOLE_SIZE,
    WGPUBindGroupLayoutEntry, WGPUBindGroupEntry,
    WGPUColor, BGL,
)
from wgpu.rendercanvas import RenderCanvas
from wgpu._ffi.nulls import null_opaque
from std import io

# ---------------------------------------------------------------------------
# Simulation constants
# ---------------------------------------------------------------------------

comptime FIRE_W      = 512       # simulation grid width
comptime FIRE_H      = 384       # simulation grid height
comptime FIRE_PIXELS = FIRE_W * FIRE_H
comptime WIN_W       = 1024      # display window width  (2× grid)
comptime WIN_H       = 768       # display window height (2× grid)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def buf_entry(binding: UInt32, buf_raw: OpaquePointer[MutUntrackedOrigin]) -> WGPUBindGroupEntry:
    """Build a WGPUBindGroupEntry for a buffer binding (no sampler / tex-view)."""
    return WGPUBindGroupEntry(
        null_opaque(), binding, buf_raw, UInt64(0), WGPU_WHOLE_SIZE,
        null_opaque(), null_opaque(),
    )


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() raises:
    print("=== wgpu-mojo: GPU Fire Simulation ===")
    print("Grid:", FIRE_W, "×", FIRE_H, "  Window:", WIN_W, "×", WIN_H)

    # ------------------------------------------------------------------
    # 1. Device
    # ------------------------------------------------------------------
    var instance = Instance()
    var adapter  = instance.request_adapter()
    var device   = adapter.request_device()

    # ------------------------------------------------------------------
    # 2. Window  (2× upscale; bilinear interp in shader gives smooth look)
    # ------------------------------------------------------------------
    var canvas = RenderCanvas(
        adapter, device, WIN_W, WIN_H,
        "wgpu-mojo · GPU Fire Simulation (compute + render)",
    )

    # ------------------------------------------------------------------
    # 3. Ping-pong storage buffers
    #    Both start cold (all zeros).  The compute shader seeds the
    #    bottom rows with heat each frame, so the fire appears quickly.
    # ------------------------------------------------------------------
    var buf_a = device.create_buffer(
        UInt64(FIRE_PIXELS * 4),
        WGPUBufferUsage.STORAGE | WGPUBufferUsage.COPY_DST,
        label="fire_a",
    )
    var buf_b = device.create_buffer(
        UInt64(FIRE_PIXELS * 4),
        WGPUBufferUsage.STORAGE | WGPUBufferUsage.COPY_DST,
        label="fire_b",
    )

    var zero_data = List[Float32](capacity=FIRE_PIXELS)
    for _ in range(FIRE_PIXELS):
        zero_data.append(Float32(0))
    device.queue_write_data(buf_a, UInt64(0), zero_data)
    device.queue_write_data(buf_b, UInt64(0), zero_data)

    # ------------------------------------------------------------------
    # 4. Params uniform  {width, height, time, frame}  — 4 × f32 = 16 B
    # ------------------------------------------------------------------
    var params_buf = device.create_buffer(
        UInt64(16),
        WGPUBufferUsage.UNIFORM | WGPUBufferUsage.COPY_DST,
        label="fire_params",
    )

    # ------------------------------------------------------------------
    # 5. Shaders
    # ------------------------------------------------------------------
    var compute_shader = device.create_shader_module_wgsl(
        open("wgsl/fire_compute.wgsl", "r").read(), "fire_compute",
    )
    var render_shader = device.create_shader_module_wgsl(
        open("wgsl/fire_render.wgsl", "r").read(), "fire_render",
    )

    # ------------------------------------------------------------------
    # 6. Bind-group layouts
    # ------------------------------------------------------------------
    # Compute BGL:
    #   slot 0 — fire_in  (read-only storage,  COMPUTE)
    #   slot 1 — fire_out (read-write storage, COMPUTE)
    #   slot 2 — params   (uniform,            COMPUTE)
    var c_bgl_entries: List[WGPUBindGroupLayoutEntry] = [
        BGL.buffer_storage(UInt32(0), WGPUShaderStage.COMPUTE.value, read_only=True),
        BGL.buffer_storage(UInt32(1), WGPUShaderStage.COMPUTE.value, read_only=False),
        BGL.buffer_uniform(UInt32(2), WGPUShaderStage.COMPUTE.value),
    ]
    var bgl_compute = device.create_bind_group_layout(c_bgl_entries, "fire_compute_bgl")

    # Render BGL:
    #   slot 0 — fire     (read-only storage,  FRAGMENT)
    #   slot 1 — params   (uniform,            FRAGMENT)
    var r_bgl_entries: List[WGPUBindGroupLayoutEntry] = [
        BGL.buffer_storage(UInt32(0), WGPUShaderStage.FRAGMENT.value, read_only=True),
        BGL.buffer_uniform(UInt32(1), WGPUShaderStage.FRAGMENT.value),
    ]
    var bgl_render = device.create_bind_group_layout(r_bgl_entries, "fire_render_bgl")

    # ------------------------------------------------------------------
    # 7. Pipeline layouts
    # ------------------------------------------------------------------
    var pl_compute = device.create_pipeline_layout(bgl_compute, "fire_compute_pl")
    var pl_render  = device.create_pipeline_layout(bgl_render,  "fire_render_pl")

    # ------------------------------------------------------------------
    # 8. Pipelines
    # ------------------------------------------------------------------
    var compute_pipeline = device.create_compute_pipeline(
        compute_shader, "cs_main", pl_compute, "fire_compute_pipeline",
    )
    var render_pipeline = device.create_render_pipeline(
        render_shader, "vs_main", "fs_main",
        canvas.surface_format(), pl_render,
        primitive_topology=UInt32(4),   # TriangleList
        label="fire_render_pipeline",
    )

    # Shaders and pipeline layouts not needed past pipeline creation
    _ = compute_shader^
    _ = render_shader^
    _ = pl_compute^
    _ = pl_render^

    # ------------------------------------------------------------------
    # 9. Bind groups  (four: two compute directions + two render sources)
    #
    # Lifetime note: buf_a and buf_b are explicitly consumed via `^` AFTER
    # the render loop (see step 12) so that Mojo's ASAP drop analysis keeps
    # them alive through all bind-group creations and the entire loop.
    # ------------------------------------------------------------------

    # Compute A→B  (even frames: read A, write B)
    var entries_a2b: List[WGPUBindGroupEntry] = [
        buf_entry(UInt32(0), buf_a.handle().raw),
        buf_entry(UInt32(1), buf_b.handle().raw),
        buf_entry(UInt32(2), params_buf.handle().raw),
    ]
    var bg_c_a2b = device.create_bind_group(bgl_compute, entries_a2b, "bg_c_a2b")

    # Compute B→A  (odd frames: read B, write A)
    var entries_b2a: List[WGPUBindGroupEntry] = [
        buf_entry(UInt32(0), buf_b.handle().raw),
        buf_entry(UInt32(1), buf_a.handle().raw),
        buf_entry(UInt32(2), params_buf.handle().raw),
    ]
    var bg_c_b2a = device.create_bind_group(bgl_compute, entries_b2a, "bg_c_b2a")

    # Render B  (display buf_b — output of A→B compute)
    var entries_r_b: List[WGPUBindGroupEntry] = [
        buf_entry(UInt32(0), buf_b.handle().raw),
        buf_entry(UInt32(1), params_buf.handle().raw),
    ]
    var bg_r_b = device.create_bind_group(bgl_render, entries_r_b, "bg_r_b")

    # Render A  (display buf_a — output of B→A compute)
    var entries_r_a: List[WGPUBindGroupEntry] = [
        buf_entry(UInt32(0), buf_a.handle().raw),
        buf_entry(UInt32(1), params_buf.handle().raw),
    ]
    var bg_r_a = device.create_bind_group(bgl_render, entries_r_a, "bg_r_a")

    # BGLs not needed after bind group creation
    _ = bgl_compute^
    _ = bgl_render^

    print("Running — close the window to stop.")

    # ------------------------------------------------------------------
    # 10. Render loop
    # ------------------------------------------------------------------
    var start_time = io.time.perf_counter()
    var frame_idx  = 0

    while canvas.is_open():
        var elapsed = Float32((io.time.perf_counter() - start_time) / 1e9)
        canvas.poll()

        var frame = canvas.next_frame()
        if not frame.is_renderable():
            continue

        # Update params uniform each frame
        var params_data = List[Float32](capacity=4)
        params_data.append(Float32(FIRE_W))
        params_data.append(Float32(FIRE_H))
        params_data.append(elapsed)
        params_data.append(Float32(frame_idx))
        device.queue_write_data(params_buf, UInt64(0), params_data)

        var enc = device.create_command_encoder("fire_frame")

        # ── Compute pass ─────────────────────────────────────────────
        var cpass = enc.begin_compute_pass("fire_compute")
        cpass.set_pipeline(compute_pipeline)
        if frame_idx % 2 == 0:
            cpass.set_bind_group(UInt32(0), bg_c_a2b)   # A→B
        else:
            cpass.set_bind_group(UInt32(0), bg_c_b2a)   # B→A
        cpass.dispatch_workgroups(
            UInt32(FIRE_W // 8), UInt32(FIRE_H // 8), UInt32(1),
        )
        cpass^.end()

        # ── Render pass ──────────────────────────────────────────────
        var rpass = enc.begin_surface_clear_pass(
            frame.texture,
            WGPUColor(Float64(0), Float64(0), Float64(0), Float64(1)),
            "fire_render_pass",
        )
        rpass.set_pipeline(render_pipeline)
        if frame_idx % 2 == 0:
            rpass.set_bind_group(UInt32(0), bg_r_b)     # display B
        else:
            rpass.set_bind_group(UInt32(0), bg_r_a)     # display A
        rpass.draw(UInt32(6), UInt32(1), UInt32(0), UInt32(0))
        rpass^.end()

        var cmd = enc^.finish()
        device.queue_submit(cmd)
        canvas.present()

        frame_idx += 1

    print("Done. Rendered", frame_idx, "frames.")

    # ------------------------------------------------------------------
    # 11. Explicit lifetime pins for storage buffers
    #
    # buf_a and buf_b are not referenced directly inside the render loop
    # (their handles live inside the bind groups).  Without these pins,
    # Mojo's ASAP drop would release them after the last `handle().raw`
    # call above, causing a wgpu validation error during bind-group creation.
    # Placing the `^` consume here makes the render loop part of their
    # required lifetime.
    # ------------------------------------------------------------------
    _ = buf_a^
    _ = buf_b^
