"""Must FAIL to compile: every encoder is `not Deinitable`.

Run by scripts/check-compile.sh, which expects one
"abandoned without being explicitly destroyed" error per function below.
Dropping an encoder without end()/finish()/abandon() has to be a compile
error, not a leaked wgpu-native handle.
"""

from wgpu.command import CommandEncoder
from wgpu.compute_pass import ComputePassEncoder
from wgpu.render_pass import RenderPassEncoder, FrameRenderPass
from wgpu.render_bundle import RenderBundleEncoder


def drop_command_encoder(var e: CommandEncoder):
    pass


def drop_compute_pass(var e: ComputePassEncoder):
    pass


def drop_render_pass(var e: RenderPassEncoder):
    pass


def drop_frame_render_pass(var e: FrameRenderPass):
    pass


def drop_render_bundle_encoder(var e: RenderBundleEncoder):
    pass


def main():
    pass
