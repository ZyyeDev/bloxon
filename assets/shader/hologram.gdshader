shader_type spatial;

uniform float Emission_Power = 1.0;
uniform vec3 Color:source_color;

group_uniforms Fresnel;
uniform sampler2D Fresnel_Noise_Texture:source_color;
uniform vec3 Fresnel_Color : source_color;
uniform float Fresnel_Power : hint_range(0.1, 10.0) = 3.0;

group_uniforms Lines_Alpha;
uniform sampler2D Line_Texture:source_color;
uniform float Repetitions = 2.0;
uniform float Speed = 1.0;

group_uniforms Alpha_Fade;
uniform sampler2D Fade_Texture:source_color;
uniform float Fade_Offset = 0.0;
uniform float Fade_Scale = 1.0;

group_uniforms Lines_Color;
uniform sampler2D Color_Line_Texture:source_color;
uniform float Color_Line_Repetitions = 2.0;
uniform float Color_Line_Speed = 1.0;

group_uniforms Vertex_Shift;
uniform sampler2D Vertex_Shift_Texture:source_color;
uniform float Vertex_Shift_Repetitions = 2.0;
uniform float Vertex_Shift_Speed = 1.0;
uniform float Shift_Power = 0.2;
uniform float Shift_X_Mult = 1.0;
uniform float Shift_Z_Mult = 1.0;


varying vec3 Wave_WorldCoords;
void vertex() {
	
	Wave_WorldCoords = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	vec2 uv = UV;
	uv.y = Wave_WorldCoords.y;
	uv.y = fract(uv.y * Vertex_Shift_Repetitions);
	uv.y += fract(TIME * -Vertex_Shift_Speed);
	float shift = texture(Vertex_Shift_Texture, uv).r * Shift_Power;

	VERTEX.x += shift * Shift_X_Mult;
	VERTEX.z += shift * Shift_Z_Mult;

}

void fragment() {
	float Fresnel = pow(1.0 - dot(NORMAL, VIEW), Fresnel_Power);
	float Noise_Value = texture(Fresnel_Noise_Texture,UV).r;
	float Noise_Fresnel = Fresnel * Noise_Value;
	
	vec3 Final_Color = mix(Color,Fresnel_Color,Noise_Fresnel);
	
	
	vec2 uv = UV;
	uv.y = Wave_WorldCoords.y;
	uv.y = fract(uv.y * Repetitions);
	uv.y += fract(TIME * -Speed);
	float Line_Alpha = texture(Line_Texture,uv).a;
	
	
	vec2 uv2 = UV;
	uv2.y = Wave_WorldCoords.y;
	uv2.y = fract(uv2.y * Color_Line_Repetitions);
	uv2.y += fract(TIME * -Color_Line_Speed);
	vec3 Line_Color = texture(Color_Line_Texture,uv2).rgb;
	
	Final_Color += Line_Color;
	
	
	vec2 uv3 = UV;
	uv3.y = (Wave_WorldCoords.y + Fade_Offset) * Fade_Scale;
	float Fade_Value = texture(Fade_Texture,uv3).a;
	
	ALBEDO = Final_Color;
	EMISSION = Final_Color * Emission_Power;
	ALPHA = Line_Alpha * Fade_Value;
	
}

