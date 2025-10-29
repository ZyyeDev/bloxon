shader_type canvas_item;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, repeat_disable, filter_nearest;
uniform float sigma : hint_range(0.1, 10.0) = 3.0; // smaller sigma for mobile

// Precompute Gaussian weights (normalized)
vec4 blur9(sampler2D tex, vec2 uv, vec2 pixel_size) {
    // fixed offsets (-4..+4) to approximate Gaussian
    float w0 = 0.2270270270;
    float w1 = 0.1945945946;
    float w2 = 0.1216216216;
    float w3 = 0.0540540541;
    float w4 = 0.0162162162;

    vec3 result = texture(tex, uv).rgb * w0;

    for(int i = 1; i <= 4; i++){
        vec2 offset = vec2(float(i)) * pixel_size * sigma;
        float weight = i==1 ? w1 : (i==2 ? w2 : (i==3 ? w3 : w4));
        result += texture(tex, uv + offset).rgb * weight;
        result += texture(tex, uv - offset).rgb * weight;
    }
    return vec4(result,1.0);
}

void fragment() {
    COLOR = blur9(SCREEN_TEXTURE, SCREEN_UV, SCREEN_PIXEL_SIZE);
}
