shader_type canvas_item;

uniform float contrast : hint_range(1.0, 3.0) = 1.5;
uniform float sharpen : hint_range(0.0, 1.0) = 0.5;

void fragment() {
    vec4 texture_color = texture(TEXTURE, UV);
    
    vec4 final_color = COLOR;
    
    vec4 sum_alpha = vec4(0.0);
    vec2 size = 1.0 / TEXTURE_PIXEL_SIZE;
    
    sum_alpha += texture(TEXTURE, UV + vec2(0.0, 1.0) / size).a * -sharpen;
    sum_alpha += texture(TEXTURE, UV + vec2(0.0, -1.0) / size).a * -sharpen;
    sum_alpha += texture(TEXTURE, UV + vec2(1.0, 0.0) / size).a * -sharpen;
    sum_alpha += texture(TEXTURE, UV + vec2(-1.0, 0.0) / size).a * -sharpen;
    
    sum_alpha += texture_color.a * (1.0 + 4.0 * sharpen);
    
    float final_alpha = pow(sum_alpha.a, contrast);
    
    COLOR = vec4(final_color.rgb, final_alpha);
}