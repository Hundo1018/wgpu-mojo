"""Wgpu.web — frame-driven hosting for the browser target (#14).

Nothing here blocks: `GPUBoot.step()` and the `*Request.ready()` calls it
uses are meant to be called once per frame from the host's loop
(requestAnimationFrame on the web). They also work natively.
"""
