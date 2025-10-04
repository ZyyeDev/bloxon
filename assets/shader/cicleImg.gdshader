shader_type canvas_item;

void fragment() {
    vec2 uv = UV * 2.0 - 1.0; // center UVs
    float dist = length(uv);

    if (dist > 1.0) {
        discard; // outside circle -> transparent
    }

    COLOR = texture(TEXTURE, UV);
}
