// Hand-written implementations of the webgpu.h functions listed in
// implemented.txt (#17). Each takes the runtime first, then the wasm arguments:
// i32 as Number, i64 and pointers as BigInt. Struct layouts come from
// webgpu_layout.json through rt.read().
import { WHOLE_SIZE } from './webgpu_runtime.mjs';

const lbl = (sv) => (sv ? { label: sv } : {});
const MAP_OK = 1, REQ_OK = 1, REQ_UNAVAILABLE = 3, REQ_ERROR = 4, MAP_ERROR = 3;

// Queue the callback described by a *CallbackInfo struct. `args` builds the
// callback's wasm arguments after (status, ...): they are all i64/i32 scalars.
function completion(rt, infoName, infoPtr, promise, onOk, onFail) {
  const info = rt.read(infoName, infoPtr);
  const cb = info.callback, ud1 = info.userdata1, ud2 = info.userdata2;
  const future = rt.newFuture();
  const done = (build) => rt.defer(() => { rt.cbLog.push(future); build(cb, ud1, ud2); });
  promise.then(
    (v) => done(onOk(v)),
    (e) => done(onFail(e)),
  );
  return future;
}

// Message strings live in wasm memory only for the callback's duration.
function withMessage(rt, text, fn) {
  const [p, n] = rt.str_in(text);
  try { return fn(p, BigInt(n)); } finally { rt.free(p); }
}

const bufferOf = (rt, h) => rt.get(h).buffer;

function releaseMapped(rt, h, commit) {
  const ranges = rt.mapped.get(h) ?? [];
  for (const r of ranges) {
    if (commit) new Uint8Array(r.ab).set(rt.bytes(r.ptr, r.size));
    rt.free(r.ptr);
  }
  rt.mapped.delete(h);
}

function mappedRange(rt, h, offset, size) {
  const o = rt.get(h);
  const off = Number(offset);
  const n = size === WHOLE_SIZE ? o.buffer.size - off : Number(size);
  const ab = o.buffer.getMappedRange(off, n);
  const ptr = rt.alloc(Math.max(n, 1));
  rt.u8.set(new Uint8Array(ab), Number(ptr));
  const list = rt.mapped.get(h) ?? [];
  list.push({ ptr, ab, size: n });
  rt.mapped.set(h, list);
  return ptr;
}

function enumOrUndef(rt, type, v) { return rt.optEnum(type, v); }

function bindingEntry(rt, e) {
  const out = { binding: e.binding, visibility: Number(e.visibility) };
  const b = e.buffer, s = e.sampler, t = e.texture, st = e.storageTexture;
  if (b.type !== 0) {
    out.buffer = { type: rt.enumStr('BufferBindingType', b.type), hasDynamicOffset: !!b.hasDynamicOffset };
    if (b.minBindingSize) out.buffer.minBindingSize = Number(b.minBindingSize);
  } else if (s.type !== 0) {
    out.sampler = { type: rt.enumStr('SamplerBindingType', s.type) };
  } else if (t.sampleType !== 0) {
    out.texture = { sampleType: rt.enumStr('TextureSampleType', t.sampleType), multisampled: !!t.multisampled };
    const vd = enumOrUndef(rt, 'TextureViewDimension', t.viewDimension);
    if (vd) out.texture.viewDimension = vd;
  } else if (st.access !== 0) {
    out.storageTexture = { access: rt.enumStr('StorageTextureAccess', st.access), format: rt.enumStr('TextureFormat', st.format) };
    const vd = enumOrUndef(rt, 'TextureViewDimension', st.viewDimension);
    if (vd) out.storageTexture.viewDimension = vd;
  }
  return out;
}

export const impl = {
  wgpuCreateInstance(rt, desc) { return rt.put({ kind: 'instance' }); },
  wgpuInstanceRelease(rt, h) { rt.drop(h); },
  wgpuInstanceProcessEvents(rt, h) { rt.drain(); },

  wgpuInstanceRequestAdapter(rt, inst, optsPtr, infoPtr) {
    const o = optsPtr ? rt.read('WGPURequestAdapterOptions', optsPtr) : null;
    const opts = {};
    if (o) {
      const pp = rt.optEnum('PowerPreference', o.powerPreference);
      if (pp) opts.powerPreference = pp;
      if (o.forceFallbackAdapter) opts.forceFallbackAdapter = true;
    }
    const p = navigator.gpu ? navigator.gpu.requestAdapter(opts) : Promise.resolve(null);
    return completion(rt, 'WGPURequestAdapterCallbackInfo', infoPtr, p,
      (adapter) => (cb, u1, u2) => {
        if (!adapter) {
          withMessage(rt, 'no WebGPU adapter', (mp, ml) => rt.call_fn(cb, REQ_UNAVAILABLE, 0n, mp, ml, u1, u2));
        } else {
          rt.call_fn(cb, REQ_OK, rt.put({ kind: 'adapter', adapter }), 0n, 0n, u1, u2);
        }
      },
      (e) => (cb, u1, u2) => withMessage(rt, String(e), (mp, ml) => rt.call_fn(cb, REQ_ERROR, 0n, mp, ml, u1, u2)));
  },
  wgpuAdapterRelease(rt, h) { rt.drop(h); },

  wgpuAdapterRequestDevice(rt, adapterH, descPtr, infoPtr) {
    const adapter = rt.get(adapterH).adapter;
    const d = descPtr ? rt.read('WGPUDeviceDescriptor', descPtr) : null;
    const desc = {};
    if (d) {
      Object.assign(desc, lbl(d.label));
      const feats = rt.u64s(d.requiredFeatures, d.requiredFeatureCount).length
        ? Array.from({ length: Number(d.requiredFeatureCount) }, (_, i) =>
            rt.enumStr('FeatureName', rt.view.getUint32(Number(d.requiredFeatures) + i * 4, true)))
        : [];
      if (feats.length) desc.requiredFeatures = feats;
      if (d.requiredLimits) {
        const lim = rt.read('WGPULimits', d.requiredLimits), req = {};
        for (const f of rt.layout.structs.WGPULimits.fields) {
          if (f.n === 'nextInChain') continue;
          const v = lim[f.n];
          const undef = f.k === 'u64' ? 0xFFFFFFFFFFFFFFFFn : 0xFFFFFFFF;
          if (v !== undef) req[f.n] = Number(v);
        }
        desc.requiredLimits = req;
      }
    }
    const p = adapter.requestDevice(desc);
    return completion(rt, 'WGPURequestDeviceCallbackInfo', infoPtr, p,
      (device) => (cb, u1, u2) => {
        device.addEventListener('uncapturederror', (ev) => {
          rt.errors.push(ev.error.message);
          console.error('wgpu uncaptured error:', ev.error.message);
        });
        rt.call_fn(cb, REQ_OK, rt.put({ kind: 'device', device }), 0n, 0n, u1, u2);
      },
      (e) => (cb, u1, u2) => withMessage(rt, String(e), (mp, ml) => rt.call_fn(cb, REQ_ERROR, 0n, mp, ml, u1, u2)));
  },
  wgpuDeviceRelease(rt, h) { rt.drop(h); },
  wgpuDeviceGetQueue(rt, h) { return rt.put({ kind: 'queue', queue: rt.get(h).device.queue }); },
  wgpuQueueRelease(rt, h) { rt.drop(h); },

  wgpuDeviceCreateBuffer(rt, dev, ptr) {
    const d = rt.read('WGPUBufferDescriptor', ptr);
    const buffer = rt.get(dev).device.createBuffer({
      ...lbl(d.label), size: Number(d.size), usage: Number(d.usage), mappedAtCreation: !!d.mappedAtCreation,
    });
    return rt.put({ kind: 'buffer', buffer });
  },
  wgpuBufferRelease(rt, h) { releaseMapped(rt, h, false); rt.drop(h); },
  wgpuBufferGetMappedRange(rt, h, off, size) { return mappedRange(rt, h, off, size); },
  wgpuBufferGetConstMappedRange(rt, h, off, size) { return mappedRange(rt, h, off, size); },
  wgpuBufferUnmap(rt, h) {
    releaseMapped(rt, h, true);
    rt.get(h).buffer.unmap();
  },
  wgpuBufferMapAsync(rt, h, mode, off, size, infoPtr) {
    const buffer = rt.get(h).buffer;
    const n = size === WHOLE_SIZE ? undefined : Number(size);
    return completion(rt, 'WGPUBufferMapCallbackInfo', infoPtr, buffer.mapAsync(Number(mode), Number(off), n),
      () => (cb, u1, u2) => rt.call_fn(cb, MAP_OK, 0n, 0n, u1, u2),
      (e) => (cb, u1, u2) => withMessage(rt, String(e), (mp, ml) => rt.call_fn(cb, MAP_ERROR, mp, ml, u1, u2)));
  },

  wgpuDeviceCreateShaderModule(rt, dev, ptr) {
    const d = rt.read('WGPUShaderModuleDescriptor', ptr);
    const w = rt.chain(d.nextInChain, 'ShaderSourceWGSL');
    if (w === null) rt.trap('wgpuDeviceCreateShaderModule: only a WGSL source chain is supported on web');
    const code = rt.read('WGPUShaderSourceWGSL', w).code;
    return rt.put({ kind: 'shader', module: rt.get(dev).device.createShaderModule({ ...lbl(d.label), code }) });
  },
  wgpuShaderModuleRelease(rt, h) { rt.drop(h); },

  wgpuDeviceCreateBindGroupLayout(rt, dev, ptr) {
    const d = rt.read('WGPUBindGroupLayoutDescriptor', ptr);
    const entries = rt.array('WGPUBindGroupLayoutEntry', d.entries, d.entryCount).map((e) => bindingEntry(rt, e));
    return rt.put({ kind: 'bgl', layout: rt.get(dev).device.createBindGroupLayout({ ...lbl(d.label), entries }) });
  },
  wgpuBindGroupLayoutRelease(rt, h) { rt.drop(h); },

  wgpuDeviceCreatePipelineLayout(rt, dev, ptr) {
    const d = rt.read('WGPUPipelineLayoutDescriptor', ptr);
    const bindGroupLayouts = rt.u64s(d.bindGroupLayouts, d.bindGroupLayoutCount).map((h) => rt.get(h).layout);
    return rt.put({ kind: 'pl', layout: rt.get(dev).device.createPipelineLayout({ ...lbl(d.label), bindGroupLayouts }) });
  },
  wgpuPipelineLayoutRelease(rt, h) { rt.drop(h); },

  wgpuDeviceCreateComputePipeline(rt, dev, ptr) {
    const d = rt.read('WGPUComputePipelineDescriptor', ptr);
    const c = d.compute;
    const desc = { ...lbl(d.label), layout: d.layout ? rt.get(d.layout).layout : 'auto',
      compute: { module: rt.get(c.module).module } };
    if (c.entryPoint) desc.compute.entryPoint = c.entryPoint;
    return rt.put({ kind: 'cpipeline', pipeline: rt.get(dev).device.createComputePipeline(desc) });
  },
  wgpuComputePipelineRelease(rt, h) { rt.drop(h); },

  wgpuDeviceCreateBindGroup(rt, dev, ptr) {
    const d = rt.read('WGPUBindGroupDescriptor', ptr);
    const entries = rt.array('WGPUBindGroupEntry', d.entries, d.entryCount).map((e) => {
      const out = { binding: e.binding };
      if (e.buffer) {
        out.resource = { buffer: rt.get(e.buffer).buffer, offset: Number(e.offset) };
        if (e.size !== WHOLE_SIZE) out.resource.size = Number(e.size);
      } else if (e.sampler) out.resource = rt.get(e.sampler).sampler;
      else out.resource = rt.get(e.textureView).view;
      return out;
    });
    return rt.put({ kind: 'bg', group: rt.get(dev).device.createBindGroup({ ...lbl(d.label), layout: rt.get(d.layout).layout, entries }) });
  },
  wgpuBindGroupRelease(rt, h) { rt.drop(h); },

  wgpuDeviceCreateCommandEncoder(rt, dev, ptr) {
    const d = ptr ? rt.read('WGPUCommandEncoderDescriptor', ptr) : null;
    return rt.put({ kind: 'encoder', encoder: rt.get(dev).device.createCommandEncoder(d ? lbl(d.label) : {}) });
  },
  wgpuCommandEncoderRelease(rt, h) { rt.drop(h); },
  wgpuCommandEncoderFinish(rt, enc, ptr) {
    const d = ptr ? rt.read('WGPUCommandBufferDescriptor', ptr) : null;
    return rt.put({ kind: 'cmdbuf', cmd: rt.get(enc).encoder.finish(d ? lbl(d.label) : {}) });
  },
  wgpuCommandBufferRelease(rt, h) { rt.drop(h); },
  wgpuCommandEncoderCopyBufferToBuffer(rt, enc, src, so, dst, doff, size) {
    rt.get(enc).encoder.copyBufferToBuffer(bufferOf(rt, src), Number(so), bufferOf(rt, dst), Number(doff), Number(size));
  },

  wgpuCommandEncoderBeginComputePass(rt, enc, ptr) {
    const d = ptr ? rt.read('WGPUComputePassDescriptor', ptr) : null;
    return rt.put({ kind: 'cpass', pass: rt.get(enc).encoder.beginComputePass(d ? lbl(d.label) : {}) });
  },
  wgpuComputePassEncoderSetPipeline(rt, pass, pl) { rt.get(pass).pass.setPipeline(rt.get(pl).pipeline); },
  wgpuComputePassEncoderSetBindGroup(rt, pass, index, bg, dynCount, dynPtr) {
    const dyn = [];
    for (let i = 0; i < Number(dynCount); i++) dyn.push(rt.view.getUint32(Number(dynPtr) + i * 4, true));
    rt.get(pass).pass.setBindGroup(index, bg ? rt.get(bg).group : null, dyn);
  },
  wgpuComputePassEncoderDispatchWorkgroups(rt, pass, x, y, z) { rt.get(pass).pass.dispatchWorkgroups(x, y, z); },
  wgpuComputePassEncoderEnd(rt, pass) { rt.get(pass).pass.end(); },
  wgpuComputePassEncoderRelease(rt, h) { rt.drop(h); },

  wgpuQueueSubmit(rt, q, count, ptr) {
    rt.get(q).queue.submit(rt.u64s(ptr, count).map((h) => rt.get(h).cmd));
  },
  wgpuQueueWriteBuffer(rt, q, buf, off, data, size) {
    rt.get(q).queue.writeBuffer(bufferOf(rt, buf), Number(off), rt.bytes(data, size).slice());
  },
};

const UNDEF32 = 0xFFFFFFFF;
const def = (v) => (v === UNDEF32 ? undefined : v);

function blendComponent(rt, b) {
  return { operation: rt.optEnum('BlendOperation', b.operation) ?? 'add',
           srcFactor: rt.optEnum('BlendFactor', b.srcFactor) ?? 'one',
           dstFactor: rt.optEnum('BlendFactor', b.dstFactor) ?? 'zero' };
}

function stencilFace(rt, f) {
  return { compare: rt.optEnum('CompareFunction', f.compare) ?? 'always',
           failOp: rt.optEnum('StencilOperation', f.failOp) ?? 'keep',
           depthFailOp: rt.optEnum('StencilOperation', f.depthFailOp) ?? 'keep',
           passOp: rt.optEnum('StencilOperation', f.passOp) ?? 'keep' };
}

function programmable(rt, st) {
  const out = { module: rt.get(st.module).module };
  if (st.entryPoint) out.entryPoint = st.entryPoint;
  return out;
}

function renderPipelineDesc(rt, d) {
  const v = d.vertex;
  const vertex = programmable(rt, v);
  vertex.buffers = rt.array('WGPUVertexBufferLayout', v.buffers, v.bufferCount).map((b) => ({
    arrayStride: Number(b.arrayStride),
    stepMode: rt.optEnum('VertexStepMode', b.stepMode) ?? 'vertex',
    attributes: rt.array('WGPUVertexAttribute', b.attributes, b.attributeCount).map((a) => ({
      format: rt.enumStr('VertexFormat', a.format), offset: Number(a.offset), shaderLocation: a.shaderLocation })),
  }));
  const p = d.primitive;
  const primitive = {};
  for (const [f, type, key] of [['topology', 'PrimitiveTopology', 'topology'], ['stripIndexFormat', 'IndexFormat', 'stripIndexFormat'],
                                ['frontFace', 'FrontFace', 'frontFace'], ['cullMode', 'CullMode', 'cullMode']]) {
    const e = rt.optEnum(type, p[f]);
    if (e) primitive[key] = e;
  }
  if (p.unclippedDepth) primitive.unclippedDepth = true;
  const m = d.multisample;
  const desc = { ...lbl(d.label), layout: d.layout ? rt.get(d.layout).layout : 'auto', vertex, primitive,
    multisample: { count: m.count || 1, mask: m.mask, alphaToCoverageEnabled: !!m.alphaToCoverageEnabled } };
  if (d.depthStencil) {
    const ds = rt.read('WGPUDepthStencilState', d.depthStencil);
    desc.depthStencil = { format: rt.enumStr('TextureFormat', ds.format), depthWriteEnabled: !!ds.depthWriteEnabled,
      depthCompare: rt.optEnum('CompareFunction', ds.depthCompare) ?? 'always',
      stencilFront: stencilFace(rt, ds.stencilFront), stencilBack: stencilFace(rt, ds.stencilBack),
      stencilReadMask: ds.stencilReadMask, stencilWriteMask: ds.stencilWriteMask,
      depthBias: ds.depthBias, depthBiasSlopeScale: ds.depthBiasSlopeScale, depthBiasClamp: ds.depthBiasClamp };
  }
  if (d.fragment) {
    const f = rt.read('WGPUFragmentState', d.fragment);
    const fragment = programmable(rt, f);
    fragment.targets = rt.array('WGPUColorTargetState', f.targets, f.targetCount).map((t) => {
      if (t.format === 0) return null;
      const out = { format: rt.enumStr('TextureFormat', t.format), writeMask: Number(t.writeMask) };
      if (t.blend) {
        const b = rt.read('WGPUBlendState', t.blend);
        out.blend = { color: blendComponent(rt, b.color), alpha: blendComponent(rt, b.alpha) };
      }
      return out;
    });
    desc.fragment = fragment;
  }
  return desc;
}

function writeOut(rt, ptr, off, kind, v) {
  if (kind === 'u32') rt.view.setUint32(Number(ptr) + off, v, true);
  else rt.view.setBigUint64(Number(ptr) + off, BigInt(v), true);
}

Object.assign(impl, {
  wgpuAdapterGetInfo(rt, adapterH, infoPtr) {
    const info = rt.get(adapterH).adapter.info ?? {};
    const sv = (off, text) => {
      const [p, n] = rt.str_in(text ?? '');
      writeOut(rt, infoPtr, off, 'u64', p); writeOut(rt, infoPtr, off + 8, 'u64', n);
    };
    sv(8, info.vendor); sv(24, info.architecture); sv(40, info.device); sv(56, info.description);
    writeOut(rt, infoPtr, 72, 'u32', 2);   // BackendType_WebGPU
    writeOut(rt, infoPtr, 76, 'u32', 4);   // AdapterType_Unknown
    return 1;                              // Status_Success
  },

  wgpuInstanceCreateSurface(rt, inst, ptr) {
    const d = rt.read('WGPUSurfaceDescriptor', ptr);
    const c = rt.chain(d.nextInChain, 'SurfaceSourceCanvasHTMLSelector');
    if (c === null) rt.trap('wgpuInstanceCreateSurface: only a canvas selector chain is supported on web');
    const selector = rt.read('WGPUSurfaceSourceCanvasHTMLSelector', c).selector;
    const canvas = document.querySelector(selector);
    const ctx = canvas && canvas.getContext('webgpu');
    return ctx ? rt.put({ kind: 'surface', canvas, ctx }) : 0n;
  },
  wgpuSurfaceRelease(rt, h) { rt.drop(h); },
  wgpuSurfaceGetCapabilities(rt, surf, adapter, ptr) {
    const preferred = navigator.gpu.getPreferredCanvasFormat();
    const formats = [preferred, preferred === 'bgra8unorm' ? 'rgba8unorm' : 'bgra8unorm'];
    const put = (offCount, offPtr, ints) => {
      const mem = rt.alloc(ints.length * 4);
      ints.forEach((v, i) => rt.view.setUint32(Number(mem) + i * 4, v, true));
      writeOut(rt, ptr, offCount, 'u64', ints.length); writeOut(rt, ptr, offPtr, 'u64', mem);
    };
    writeOut(rt, ptr, 8, 'u64', 0x1F);                                  // CopySrc|CopyDst|TextureBinding|StorageBinding|RenderAttachment
    put(16, 24, formats.map((f) => rt.enumInt('TextureFormat', f)));
    put(32, 40, [rt.enumInt('PresentMode', 'fifo')]);
    put(48, 56, [rt.enumInt('CompositeAlphaMode', 'opaque'), rt.enumInt('CompositeAlphaMode', 'premultiplied')]);
    return 1;
  },
  wgpuSurfaceCapabilitiesFreeMembers(rt, ptr) {
    // Passed by value: `ptr` points at the caller's copy.
    for (const off of [24, 40, 56]) {
      const p = rt.view.getBigUint64(Number(ptr) + off, true);
      if (p) rt.free(p);
    }
  },
  wgpuSurfaceConfigure(rt, surf, ptr) {
    const c = rt.read('WGPUSurfaceConfiguration', ptr), s = rt.get(surf);
    s.canvas.width = c.width; s.canvas.height = c.height;
    s.ctx.configure({
      device: rt.get(c.device).device, format: rt.enumStr('TextureFormat', c.format), usage: Number(c.usage),
      alphaMode: rt.optEnum('CompositeAlphaMode', c.alphaMode) ?? 'opaque',
    });
  },
  wgpuSurfaceUnconfigure(rt, surf) { rt.get(surf).ctx.unconfigure(); },
  wgpuSurfaceGetCurrentTexture(rt, surf, out) {
    const texture = rt.get(surf).ctx.getCurrentTexture();
    writeOut(rt, out, 8, 'u64', rt.put({ kind: 'texture', texture, owned: false }));
    writeOut(rt, out, 16, 'u32', 1);       // SurfaceGetCurrentTextureStatus_SuccessOptimal
  },

  wgpuDeviceCreateTexture(rt, dev, ptr) {
    const d = rt.read('WGPUTextureDescriptor', ptr), sz = d.size;
    const texture = rt.get(dev).device.createTexture({
      ...lbl(d.label), usage: Number(d.usage), dimension: rt.optEnum('TextureDimension', d.dimension) ?? '2d',
      size: { width: sz.width, height: sz.height, depthOrArrayLayers: sz.depthOrArrayLayers },
      format: rt.enumStr('TextureFormat', d.format), mipLevelCount: d.mipLevelCount, sampleCount: d.sampleCount,
    });
    return rt.put({ kind: 'texture', texture, owned: true });
  },
  wgpuTextureRelease(rt, h) { rt.drop(h); },
  wgpuTextureCreateView(rt, tex, ptr) {
    const d = ptr ? rt.read('WGPUTextureViewDescriptor', ptr) : null, desc = {};
    if (d) {
      Object.assign(desc, lbl(d.label));
      const f = rt.optEnum('TextureFormat', d.format); if (f) desc.format = f;
      const dim = rt.optEnum('TextureViewDimension', d.dimension); if (dim) desc.dimension = dim;
      desc.baseMipLevel = d.baseMipLevel;
      if (def(d.mipLevelCount) !== undefined) desc.mipLevelCount = d.mipLevelCount;
      desc.baseArrayLayer = d.baseArrayLayer;
      if (def(d.arrayLayerCount) !== undefined) desc.arrayLayerCount = d.arrayLayerCount;
      const a = rt.optEnum('TextureAspect', d.aspect); if (a) desc.aspect = a;
    }
    return rt.put({ kind: 'view', view: rt.get(tex).texture.createView(desc) });
  },
  wgpuTextureViewRelease(rt, h) { rt.drop(h); },

  wgpuDeviceCreateRenderPipeline(rt, dev, ptr) {
    const d = rt.read('WGPURenderPipelineDescriptor', ptr);
    return rt.put({ kind: 'rpipeline', pipeline: rt.get(dev).device.createRenderPipeline(renderPipelineDesc(rt, d)) });
  },
  wgpuRenderPipelineRelease(rt, h) { rt.drop(h); },

  wgpuCommandEncoderBeginRenderPass(rt, enc, ptr) {
    const d = rt.read('WGPURenderPassDescriptor', ptr);
    if (d.depthStencilAttachment) rt.trap('wgpuCommandEncoderBeginRenderPass: depth/stencil attachments are not implemented on web');
    const colorAttachments = rt.array('WGPURenderPassColorAttachment', d.colorAttachments, d.colorAttachmentCount).map((a) => {
      if (!a.view) return null;
      const out = { view: rt.get(a.view).view, loadOp: rt.optEnum('LoadOp', a.loadOp) ?? 'clear',
                    storeOp: rt.optEnum('StoreOp', a.storeOp) ?? 'store' };
      const c = a.clearValue;
      out.clearValue = { r: c.r, g: c.g, b: c.b, a: c.a };
      if (a.resolveTarget) out.resolveTarget = rt.get(a.resolveTarget).view;
      if (def(a.depthSlice) !== undefined) out.depthSlice = a.depthSlice;
      return out;
    });
    return rt.put({ kind: 'rpass', pass: rt.get(enc).encoder.beginRenderPass({ ...lbl(d.label), colorAttachments }) });
  },
  wgpuRenderPassEncoderSetPipeline(rt, pass, pl) { rt.get(pass).pass.setPipeline(rt.get(pl).pipeline); },
  wgpuRenderPassEncoderDraw(rt, pass, vc, ic, fv, fi) { rt.get(pass).pass.draw(vc, ic, fv, fi); },
  wgpuRenderPassEncoderEnd(rt, pass) { rt.get(pass).pass.end(); },
  wgpuRenderPassEncoderRelease(rt, h) { rt.drop(h); },

  wgpuCommandEncoderCopyTextureToBuffer(rt, enc, srcPtr, dstPtr, sizePtr) {
    const s = rt.read('WGPUTexelCopyTextureInfo', srcPtr), d = rt.read('WGPUTexelCopyBufferInfo', dstPtr);
    const sz = rt.read('WGPUExtent3D', sizePtr), o = s.origin, l = d.layout;
    const layout = { offset: Number(l.offset) };
    if (def(l.bytesPerRow) !== undefined) layout.bytesPerRow = l.bytesPerRow;
    if (def(l.rowsPerImage) !== undefined) layout.rowsPerImage = l.rowsPerImage;
    rt.get(enc).encoder.copyTextureToBuffer(
      { texture: rt.get(s.texture).texture, mipLevel: s.mipLevel, origin: { x: o.x, y: o.y, z: o.z } },
      { buffer: rt.get(d.buffer).buffer, ...layout },
      { width: sz.width, height: sz.height, depthOrArrayLayers: sz.depthOrArrayLayers });
  },

  wgpuAdapterRelease: impl.wgpuAdapterRelease,
});
