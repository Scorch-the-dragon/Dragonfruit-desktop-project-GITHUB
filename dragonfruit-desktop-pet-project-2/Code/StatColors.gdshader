shader_type canvas_item;
// Hunger -> red, happiness -> green, thirst -> blue. At zero, retain the
// artwork's brightness and transparency, rather than turning it solid black.
uniform vec3 care_color = vec3(1.0);
void fragment() {
	vec3 original = COLOR.rgb;
	float gray = dot(original, vec3(0.299, 0.587, 0.114));
	COLOR.rgb = mix(vec3(gray), original, care_color);
}
