// 单位描边高亮：把精灵的 alpha 轮廓填成纯色，用作"这个角色可以点"的提示。
//
// 为什么不直接用 Sprite2D.modulate 上色：modulate 是**乘法**，
// 深色精灵乘亮色只会发暗，描边根本看不出来。这里用纹理的 alpha 直接输出纯色，
// 颜色不受精灵本身明暗影响——不管精灵多黑，描边都是满亮的。
shader_type canvas_item;

uniform vec4 outline_color : source_color = vec4(1.0, 0.85, 0.35, 1.0);

void fragment() {
	float alpha = texture(TEXTURE, UV).a;
	COLOR = vec4(outline_color.rgb, outline_color.a * alpha);
}
