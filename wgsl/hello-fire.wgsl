struct FrameData {
    u_time: f32,
    // 你之後可以繼續增加變數，例如：
    // u_resolution: vec2<f32>,
};

// 宣告一個 uniform 變數 binding is FrameData
@group(0) @binding(0) var<uniform> frame_data: FrameData;

struct VertexOut {
    @builtin(position) pos: vec4<f32>,
    @location(0) uv: vec2<f32>, // 傳遞 UV 座標 (0.0~1.0)
}

// --- 頂點著色器：畫一個全螢幕的正方形 ---
@vertex
fn vs_main(@builtin(vertex_index) i: u32) -> VertexOut {
    var pos = array<vec2<f32>, 4>(
        vec2(-1.0,  1.0), // 左上
        vec2(-1.0, -1.0), // 左下
        vec2( 1.0,  1.0), // 右上
        vec2( 1.0, -1.0), // 右下
    );
    var uv = array<vec2<f32>, 4>(
        vec2(0.0, 0.0), // 左上
        vec2(0.0, 1.0), // 左下
        vec2(1.0, 0.0), // 右上
        vec2(1.0, 1.0), // 右下
    );
    var out: VertexOut;
    out.pos = vec4<f32>(pos[i], 0.0, 1.0);
    out.uv = uv[i];
    return out;
}

// --- 簡單的雜訊函式 (模擬火焰晃動) ---
fn noise(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

// --- 片元著色器：程式化生成火焰 ---
@fragment
fn fs_main(in: VertexOut) -> @location(0) vec4<f32> {
    // 1. 將 UV 座標中心化 (-1.0 ~ 1.0)，y 軸向上
    var p = (in.uv * 2.0 - 1.0) * vec2<f32>(1.0, -1.0);
    
    // 這裡我們需要一個時間變數 u_time，通常從 Mojo 傳入。
    // 為了演示，我們暫時用一個固定的數字，或者你可以嘗試手動加上它。
    let u_time = 1.0; 

    // 2. 形狀定義 (簡單的水滴形)
    var shape = length(p * vec2<f32>(1.0, 1.0 + p.y * 0.5)) - 0.5;
    
    // 3. 加入晃動效果 (Noise)
    var distortion = noise(p * 5.0 + u_time * 2.0) * 0.1;
    shape += distortion;

    // 4. 顏色混和 (根據距離形狀中心的遠近)
    var color = vec3<f32>(0.0);
    if (shape < 0.0) {
        // 火焰內部：從黃色過渡到紅色
        let t = 1.0 - abs(shape) * 2.0;
        color = mix(vec3<f32>(1.0, 0.0, 0.0), vec3<f32>(1.0, 1.0, 0.0), t);
    } else if (shape < 0.1) {
        // 火焰邊緣：淡出
        color = mix(vec3<f32>(1.0, 0.0, 0.0), vec3<f32>(0.0), shape * 10.0);
    }

    return vec4<f32>(color, 1.0);
}