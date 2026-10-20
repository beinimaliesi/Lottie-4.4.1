extends Node
## 必须同时在导出包中运行：第一帧透明，只有后台线程播放到第 15 帧后才出现 PNG。


func _ready() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(480, 320)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var animation := LottieAnimation.new()
	animation.animation_path = "res://tests/fixtures/packed_bitmap.json"
	animation.fit_box_size = Vector2i(480, 320)
	animation.dynamic_resolution = false
	animation.position = Vector2(240, 160)
	viewport.add_child(animation)
	animation.play()
	await get_tree().create_timer(1.0).timeout
	var image := viewport.get_texture().get_image()
	var pixel := image.get_pixel(240, 160)
	var passed := animation.get_frame() >= 15.0 and pixel.b > 0.8 and pixel.a > 0.8
	image.save_png("user://packed-playback-test.png")
	print(
		"PACKED_PLAYBACK_TEST ",
		"PASS" if passed else "FAIL",
		" frame=",
		animation.get_frame(),
		" pixel=",
		pixel,
	)
	get_tree().quit(0 if passed else 1)
