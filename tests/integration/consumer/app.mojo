# Minimal downstream consumer of the wgpu-mojo package.
#
# `mojo build app.mojo` (pixi run check) proves the package is importable.
# `mojo run app.mojo`   (pixi run app)   proves the consumed runtime stack works
#                                        against a real (or lavapipe) adapter.
from wgpu import Instance


def main() raises:
    var instance = Instance()
    var adapter = instance.request_adapter()
    print("wgpu-mojo consumed OK — Instance + Adapter created from package")
    _ = adapter^
    _ = instance^
