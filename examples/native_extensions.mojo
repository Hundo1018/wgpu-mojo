"""
Examples/native_extensions.mojo — Query native wgpu-native feature support.

Demonstrates:
  * requesting a device
  * checking native feature support using wgpu-native constants
  * printing support results for useful native features

Run:
    pixi run example-native-extensions
"""

from wgpu.gpu import GPU
from wgpu._native import WGPUNativeFeature


def main() raises:
    var gpu = GPU()
    var device = gpu.request_device()

    print("wgpu-native feature support:")
    var feature_list = [
        ("TextureBindingArray", WGPUNativeFeature.TextureBindingArray),
        ("SampledTextureAndStorageBufferArrayNonUniformIndexing", WGPUNativeFeature.SampledTextureAndStorageBufferArrayNonUniformIndexing),
        ("PushConstants", WGPUNativeFeature.PushConstants),
        ("StorageResourceBindingArray", WGPUNativeFeature.StorageResourceBindingArray),
        ("BufferBindingArray", WGPUNativeFeature.BufferBindingArray),
        ("VertexAttribute64bit", WGPUNativeFeature.VertexAttribute64bit),
    ]

    for (name, feature) in feature_list:
        var supported = device.has_feature(feature)
        print("  ", name, ":", supported)

    print("Done.")
