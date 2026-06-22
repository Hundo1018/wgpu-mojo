# wgpu-mojo 綁定成熟度評估（Binding Maturity Assessment）

> 評估日期：2026-06-21 ｜ 目標：wgpu-native **v29.0.0.0** ｜ Mojo：**1.0.0b3.dev2026061206**
> 方法：靜態（header ↔ 綁定符號差集、struct/enum/handle 計數、RAII 盤點）+ 動態（實際 `pixi run` build / 測試 / 範例，於本機 NVIDIA RTX 3060 + Vulkan + X11）。
> 數字均為**實測**，非估計。本文件不修改任何綁定程式碼，僅為評估與路線圖。

---

## 1. TL;DR — 總體評級

**整體：B−（pre-1.0，可實戰但需照顧）。**

綁定層本身**扎實**：函式接線 ≈79%、enum/handle 實質完整、RAII 封裝完善，且**核心 compute 與 render 路徑已在真實 GPU 上端到端跑通**（vector-add 1024 元素全對、fire/triangle/clear demo 可開窗運行）。

**專案衛生（hygiene）已追上綁定品質**：評估時 15 個 GPU 測試有 8 個無法編譯、10 個範例有 4 個壞掉（主因：`usage` 從 `UInt64` 收緊為 bitflag newtype，Mojo 語言漂移）。這些已全部修復，並加入 CI — `ci.yml` 的 compile-check job 每次 PR 攔截編譯期漂移；`nightly.yml` 每日跟蹤最新 nightly，綠燈自動 bump `pixi.lock`。

> 一句話定位：**綁定核心已可用於正式 compute/render 工作負載；但測試套件與部分範例已 bit-rot，且整體受上游 Mojo FFI 限制約束。先補測試/CI，再談 1.0。**

---

## 2. 評分 Rubric（逐維度）

| 維度 | 等級 | 依據 |
|---|---|---|
| 函式覆蓋（C symbol 接線） | **B+** | 179/226 distinct `wgpu*` ≈79%；缺口多為 AddRef/FreeMembers/平台特定，**有意義 API 覆蓋更高** |
| Struct 覆蓋 | **B−** | 81/115 webgpu.h core ≈70%（含 wgpu.h 擴充 ≈60%） |
| Enum 覆蓋 | **A** | 59 enum 群組 + 5 bitflag，對照 header 實質完整 |
| Handle 型別安全 | **A** | 20 個 newtype 覆蓋全部 WebGPU 物件，防止 raw pointer 混用 |
| Async / callback 橋接 | **B−** | 5 條核心 callback 經 C bridge 運作；pipeline-async 有 C bridge 但無 Mojo wrapper；pop-error / compilation-info 未接線 |
| RAII / 生命週期正確性 | **A−** | 每個 wrapper 都在 `__del__` 釋放；linear-type 強制 finish/end；有 QuerySet double-free 等審慎 workaround |
| 高階 ergonomics | **B** | dual-overload（raw handle / RAII）、BGL builder、facade；但 raw 描述子仍外露，錯誤訊息只有 raw status code |
| **測試覆蓋（實測）** | **C** | 非 GPU 全綠；但 **8/15 GPU 測試無法編譯**（API/nightly 漂移未同步），無 CParseError 把關 |
| **範例（實測）** | **C+** | compute / enumerate / clear / triangle / fire / native-ext 可跑；**v2 facade / texture_sample / input_demo / stylized_flame 壞掉** |
| 文件 | **B+** | README、CLAUDE.md、MOJO_ROUGH_EDGES.md、api_index.mojo 皆紮實 |
| 平台支援 | **B−** | linux-64 / osx-arm64 經 pixi 支援；surface 僅 Wayland/Xlib；缺 Windows HWND / Metal layer / Android |
| 上游 blocker 暴露度 | **C** | Mojo #3144（>16B struct-by-value 損壞）**當前 nightly 仍可重現**，整個 async 架構被迫依賴 C bridge |

---

## 3. 覆蓋率表（實測）

| 類別 | 已綁定 | 來源/總數 | 覆蓋 |
|---|---:|---|---:|
| C 函式（distinct `wgpu*`） | **179** | webgpu.h+wgpu.h 去重 226（webgpu.h 有 204 `WGPU_EXPORT`） | **≈79%** |
| Struct（描述子/型別） | **81** | webgpu.h `typedef struct` 115（+wgpu.h 21） | **≈70% / 60%** |
| Enum 群組 | **59** + 5 bitflag | webgpu.h enums | **實質完整** |
| Handle newtype | **20** | 全部 WebGPU 物件 | **100%** |
| Async callback C 橋接 | **5 核心** | request-adapter/device、buffer-map、work-done、pop-error | 核心齊全 |
| 高階 RAII wrapper 物件 | **~20** | 見 §5 | 缺獨立 Queue wrapper |

---

## 4. Gap 清單（未接線 C 符號，依性質分類）

**A. 應補（影響可用性 / 除錯體驗）**  ✅ 全部完成
- [x] `wgpuDevicePopErrorScope` — `Device.push_error_scope(filter)` / `pop_error_scope() -> String`。
- [x] `wgpuShaderModuleGetCompilationInfo` — `ShaderModule.get_compilation_info() -> List[String]`。
- [x] `wgpuDeviceCreateComputePipelineAsync` / `...RenderPipelineAsync` — `Device.create_*_pipeline_async()`。
- [x] `wgpuQueueGetTimestampPeriod` — `Device.queue_timestamp_period() -> Float32`。
- [x] `wgpu*EncoderSetImmediates` — `{Compute,Render,RenderBundle}Encoder.set_immediates(offset, size, data)`。

**B. 擴充 / 進階（可延後）**
- External texture 全系列（`wgpuExternalTexture*`）。
- `wgpuSetLogCallback`（目前只有 `set_log_level`）。

**C. 平台特定（依目標平台）**
- `wgpuTextureGetNativeMetalTexture`、`wgpuDeviceGetNativeMetalDevice`、`wgpuQueueGetNativeMetalCommandQueue`（macOS interop）。
- 缺漏 surface source struct：Windows HWND、Metal layer、Android、XCB。

**D. 刻意省略（設計取捨，需文件化）**
- `wgpu*AddRef` 全家族未接線 — RAII 採**單一所有權** + `InstanceOwner` 的 Arc，個別物件不做 wgpu refcount 共享。
  **後果**：GPU 物件**不可安全複製/多方共享 handle**；目前文件未明示，使用者可能誤用。
- 多數 `wgpu*FreeMembers` 未接線（僅 surface capabilities 有）。

---

## 5. RAII & 生命週期正確性

- **完整 `__del__` 覆蓋**：Instance / Adapter / Device(+Queue) / Buffer / Texture / TextureView / Sampler / ShaderModule / BindGroup(+Layout) / PipelineLayout / Compute·RenderPipeline / CommandBuffer / QuerySet / Surface(+Frame) / RenderCanvas 都在解構時釋放 handle。
- **Linear types**：CommandEncoder、Compute/RenderPassEncoder 以 `@explicit_destroy` 標記，**編譯期強制** `.finish()`/`.end()`/`.abandon()`，避免漏關 pass。
- **審慎 workaround（非 TODO，是對 wgpu-native v29 bug 的修補）**：
  - `query_set.mojo`：跳過 `QuerySetDestroy` 以避開 v29 的 **double-free**（Destroy 會把資源移出 registry，Release 再次 drop 造成 double-free）。
  - 多處 `_ = obj^` 把 GPU 資源 pin 到 `queue_submit`/`poll` 之後（Mojo ASAP destruction 對策）。
- **缺口**：**Queue 無獨立 wrapper**（只透過 `Device.queue_*`）。

---

## 6. 上游 Mojo 限制（限制成熟度的根因）

| 限制 | 影響 | 當前狀態 |
|---|---|---|
| **#3144** >16B struct by-value FFI 損壞 | 強制所有 async API 走 C bridge（`libwgpu_mojo_cb.so`） | **本次實測仍可重現**（probe_09 XFAIL，40B checksum mismatch） |
| Mojo `def` 無法當 C 函式指標 | callback 必須由 C 提供 | 仍然（probe_02/03/04/07 FAIL） |
| ASAP destruction | 大量 `_ = x^` pin 樣板 | 仍然 |
| `@explicit_destroy` 不可入 `List`/`Variant` | 無法做延遲 encoder 佇列 | 仍然 |
| nightly 語言漂移 | 見 §7 的測試/範例 rot | **本次新發現多處** |

---

## 7. 動態驗證結果（實測 — 本次評估的核心證據）

環境：`pixi 0.70.2`、Mojo `1.0.0b3.dev2026061206`、`libwgpu_native.so` v29、NVIDIA RTX 3060 + Intel Xe + Vulkan、X11 `DISPLAY=:1`。
**重要：所有 Mojo 指令須經 `pixi run` 執行**（直接呼叫 `mojo` 會缺少環境啟用，導致 stdlib prelude 找不到、`print` 誤報 unknown — 這本身是個易踩的坑）。

### Build
| 項目 | 結果 |
|---|---|
| `build-callbacks`（libwgpu_mojo_cb / libglfw_input_cb） | ✅ PASS |
| `build-callback-probe` | ✅ PASS |

### 非 GPU 測試（`pixi run test`）— ✅ 全綠
`test_types`(12)、`test_alloc_guard`(2)、`test_handle_newtypes`(2)、`test_lifetimes_string_view`(2)、`test_structs`(9)、`test_native_ext`(6)、`test_callback_abi`(6，含 16B struct-by-value callback)。

### ABI 探針（`tests/abi_probes/`）— 與文件一致
| Probe | 結果 | 意義 |
|---|---|---|
| 01 def abi("C") 定義 | ✅ PASS | |
| 02/03/04 取 opaque / rebind / fn-type 指派 | ❌ FAIL（預期負向探針） | Mojo def 無法當 C ptr |
| 05 get_function API | ✅ PASS | |
| 06 callback struct layout | ✅ PASS | |
| 07 PyCFunction rebind | ❌ FAIL（預期 reproducer） | |
| **09 直呼 40B struct-by-value** | **⚠ XFAIL（checksum mismatch）** | **#3144 仍活著 → C bridge 必須保留** |

### GPU 測試（15 個）— ⚠ 7 過、8 無法編譯
| 結果 | 測試 |
|---|---|
| ✅ 編譯+在 GPU 上跑過 | `test_preflight`、`test_instance`、`test_device`、`test_shader`、`test_pipeline_layout`、`test_sampler`、`test_query_set`（7） |
| ❌ **編譯失敗** | `test_buffer`、`test_bind_group`、`test_texture`、`test_render_pipeline`、`test_texture_sample`、`test_debug_groups`、`test_compute_pipeline`、`test_command_encoder`（8） |

**失敗原因分類（皆為測試/範例未同步，非綁定核心壞掉）：**
1. **`usage` newtype 收緊**（`UInt64` → `WGPUBufferUsage`/`WGPUTextureUsage`）：test_buffer / bind_group / texture / render_pipeline / texture_sample / debug_groups。
2. **方法改名** `Device.queue_write_buffer` → `queue_write_data`：test_compute_pipeline。
3. **Mojo nightly 語言變更**「member method closures not supported」：test_command_encoder。

### 範例（10 個）— ⚠ 6 可用、4 壞掉
| 結果 | 範例 | 證據 |
|---|---|---|
| ✅ 端到端跑通 | `enumerate_adapters` | 列出 Intel/NVIDIA-Vulkan/llvmpipe/NVIDIA-GL 全部 adapter |
| ✅ 端到端跑通 | `compute_add` | N=1024 向量加法**全部 1024 元素正確** |
| ✅ 編譯+開窗運行 | `clear_screen`、`triangle_window`、**`fire_simulation`**（旗艦 demo） | render loop 正常啟動 |
| ✅ 跑通 | `native_extensions` | 正常輸出 Done. |
| ❌ trait 漂移 | `compute_add_v2`（`wgpu.gpu` facade） | `WgpuComputeProgram` 不符 `ImplicitlyCopyable` → **facade 目前壞掉** |
| ❌ usage newtype | `texture_sample` | 同 §7-(1) |
| ❌ 執行期 panic | `input_demo` | 可編譯但 runtime `non-unwinding panic, abort` |
| ❌ 檔案不存在 | `stylized_flame` | `pixi.toml` 的 `example-flame` 指向不存在的 `examples/stylized_flame.mojo`（**dangling task**） |

> **結論**：綁定核心可信（compute + render 真機驗證通過），但**測試套件與部分範例已對不上現行 API/nightly**。這是「成熟度」最關鍵也最容易被靜態覆蓋率數字掩蓋的一面。

---

## 8. 優先級路線圖

### Tier 0 — 止血（最優先，恢復可信度）
- [x] **修復 8 個無法編譯的 GPU 測試 + 4 個壞掉範例**：批次把 `create_buffer/create_texture` 的 `usage` 改傳 `WGPUBufferUsage(...)`/`WGPUTextureUsage(...)`；`queue_write_buffer` → `queue_write_data`；修 `test_command_encoder` 的 member-method-closure；修 `wgpu.gpu` facade 的 `ImplicitlyCopyable`。
- [x] **加 CI**（GitHub Actions）：`ci.yml` 含 compile-check job（GPU-free）；`nightly.yml` 每日 `pixi update` + 綠燈自動 bump `pixi.lock`。
- [x] **清掉 dangling `example-flame` 任務**；修 `input_demo` runtime panic（加完整 clear pass）。
- [x] **追隨 Mojo nightly 而非釘死**：`pixi.toml` 改為 `mojo = ">=1.0.0b,<2"`，以持續 bump 的 `pixi.lock` 為可重現錨點。

### Tier 1 — 正確性 / 安全性
- [x] 補 `device.push_error_scope(filter)` / `pop_error_scope() -> String` 高階 API（讓驗證錯誤不再靜默）+ 測試 `tests/test_error_scope.mojo`。
- [x] 補 `shader.get_compilation_info() -> List[String]`（WGSL 編譯錯誤可讀回）+ 測試 `tests/test_shader.mojo`。
- [ ] **`*AddRef` 未接線**：GPU 物件（`Buffer`、`Texture`、`ShaderModule` 等）不可安全複製或跨所有者共享原始 handle — `clone()` 類方法不存在。設計上為**單一所有權 RAII**；如需共享請用 `Arc` 包裝整個高階 wrapper。補 `wgpu_native` AddRef 接線以啟用 handle-level ref-count 共享屬 **Tier 3**。

### Tier 2 — 覆蓋缺口
- [x] **RenderBundle / RenderBundleEncoder 高階 wrapper** (`wgpu/render_bundle.mojo`)：`finish()`/`abandon()` linear-type 模式、所有 draw/bind/debug/set_immediates 方法、`Device.create_render_bundle_encoder()`、`RenderPassEncoder.execute_bundles(List[RenderBundle])` overload；`tests/test_render_bundle.mojo`。
- [x] Async pipeline 建立的 Mojo wrapper：`Device.create_compute_pipeline_async()` + `Device.create_render_pipeline_async()`（AllocGuard + C bridge poll 模式，回傳同步版同型別的 `ComputePipeline`/`RenderPipeline`）。
- [x] `queue_get_timestamp_period` + `Device.queue_timestamp_period() -> Float32`。
- [x] v29 `SetImmediates`（push constants）三個 encoder 變體：`ComputePassEncoder.set_immediates()`、`RenderPassEncoder.set_immediates()`、`RenderBundleEncoder.set_immediates()`。
- [ ] 缺漏 surface source struct（依目標平台：Windows HWND / Metal layer）。

### Tier 3 — Ergonomics / 收尾
- [ ] 獨立 `Queue` wrapper。
- [ ] 以 enum + `Writable` 取代 raw `UInt32` status 的錯誤訊息。
- [ ] 補弱測試區：depth/stencil 附件、多 render pass、query 結果讀回。
- [ ] External texture（低優先）。

---

## 9. 如何複現本評估

```bash
# 靜態：header ↔ 綁定 符號差集
grep -oE '"wgpu[A-Za-z]+"' wgpu/_backend/wgpu_native/loader.mojo | sort -u > /tmp/wired.txt   # 179
grep -oE 'wgpu[A-Za-z]+\(' ffi/include/webgpu/{webgpu,wgpu}.h | grep -oE 'wgpu[A-Za-z]+' | sort -u > /tmp/declared.txt  # 226
comm -23 /tmp/declared.txt <(sed 's/"//g' /tmp/wired.txt)     # 未接線清單

# 動態（務必經 pixi run，否則 stdlib prelude 不會載入）
pixi run build-callbacks && pixi run build-callback-probe
pixi run test                                   # 非 GPU，全綠
for p in tests/abi_probes/probe_*.mojo; do pixi run mojo run -I . "$p"; done   # probe_09 = XFAIL(#3144)
for t in test_preflight test_instance test_device test_shader test_pipeline_layout test_sampler test_query_set; do
  pixi run mojo run -I . tests/$t.mojo; done     # 7 個會過
pixi run example-enumerate && pixi run example-compute    # 真機 compute/enumerate 驗證
```
