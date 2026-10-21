extends Node
## Build with lottie_lifecycle_tests=yes. Uses real ThorVG objects and rendering.

var failures := 0
var failure_messages: Array[String] = []
var case_results: Dictionary = {}
var viewport: SubViewport
var status_label: Label
var path_a := "user://lifecycle_a.json"
var path_b := "user://lifecycle_b.json"
var path_zip := "user://lifecycle_valid.lottie"
var bad_json := "user://lifecycle_bad.json"
var bad_zip := "user://lifecycle_bad.lottie"

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		failure_messages.append(message)
		push_error("LIFECYCLE: " + message)

func counts() -> Dictionary:
	return ClassDB.class_call_static("LottieAnimation", "debug_lifecycle_counts")

func write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)

func frames(amount: int = 3) -> void:
	for i in amount:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

func check_balanced(label: String) -> void:
	var stats := counts()
	check(stats.created == stats.destroyed, label + " leaked animations: " + str(stats))
	check(stats.unexpected_picture_refs == 0, label + " retained Canvas reference: " + str(stats))
	check(stats.workers == 0, label + " retained worker: " + str(stats))

func new_node(kind: String) -> Node:
	var node: Variant
	if kind == "3d":
		node = LottieAnimation3D.new()
		node.render_size = Vector2i(32, 32)
	else:
		node = LottieAnimation.new()
		node.call("debug_set_render_thread_enabled", kind == "worker")
		node.fit_box_size = Vector2i(32, 32)
		node.dynamic_resolution = false
		node.position = Vector2(16, 16)
	node.autoplay = false
	viewport.add_child(node)
	return node

func color_for(node: Node) -> Color:
	if node is LottieAnimation3D:
		return node.get_texture().get_image().get_pixel(16, 16)
	return viewport.get_texture().get_image().get_pixel(16, 16)

func packed_playback() -> void:
	var node: Variant = new_node("sync" if OS.has_feature("web") else "worker")
	node.animation_path = "res://tests/fixtures/packed_bitmap.json"
	node.play()
	await get_tree().create_timer(1.0).timeout
	await frames()
	var pixel := color_for(node)
	check(node.get_frame() >= 15.0 and pixel.b > 0.8 and pixel.a > 0.8, "packed PNG playback")
	case_results["packed_playback"] = {"frame": node.get_frame(), "pixel": str(pixel), "passed": failures == 0}
	node.queue_free()
	await frames()
	check_balanced("packed playback")

func exercise(kind: String) -> void:
	status_label.text = "Lifecycle regression: " + kind + " (100 cycles)"
	# Verify rendering survives a same-frame switch and no old result resurfaces
	# after clear. Stop/pause must retain the current animation until unload.
	var node: Variant = new_node(kind)
	node.animation_path = path_a
	node.play()
	await frames(5)
	check(color_for(node).b > 0.8, kind + " failed to render embedded PNG")
	if kind == "worker":
		for invalid in [bad_json, "user://lifecycle_missing_worker.json"]:
			node.call("debug_load_worker_path", invalid)
			await frames(5)
			var stats := counts()
			check(stats.created - stats.destroyed == 1, "worker failure retained an animation")
		node.call("debug_load_worker_path", path_a)
		await frames(5)
	node.animation_path = path_b
	await frames(5)
	check(color_for(node).r > 0.8 and color_for(node).b < 0.1, kind + " old frame after switch")
	node.pause()
	node.stop()
	check(counts().created > counts().destroyed, kind + " pause/stop unexpectedly unloaded animation")
	node.animation_path = ""
	await frames(5)
	check(color_for(node).a < 0.1, kind + " old frame after clear")
	node.queue_free()
	await frames()
	check_balanced(kind + " rendering")

	for i in 100:
		node = new_node(kind)
		node.animation_path = path_a
		node.play()
		if i % 2 == 0:
			await frames(1) # allow worker load/render to overlap the next request
		node.animation_path = path_b
		node.animation_path = path_zip
		if i % 10 == 0:
			for invalid in [bad_json, bad_zip, "user://lifecycle_missing.json"]:
				node.animation_path = invalid
				check(node.get_total_frames() == 0, kind + " retained metadata after failure")
				node.animation_path = path_a
		if i % 3 == 0:
			node.animation_path = ""
			node.animation_path = path_b
		if i % 5 == 0:
			viewport.remove_child(node)
			node.animation_path = "" # clearing detached nodes must also release
			node.free()
		else:
			node.queue_free() # includes outstanding worker requests
		await frames(1)
		check_balanced(kind + " iteration " + str(i))
	case_results[kind] = {"counts": counts(), "passed": failures == 0, "iterations": 100}
	print("LIFECYCLE ", kind, " PASS" if failures == 0 else " FAIL", " ", counts())

func concurrent_workers() -> void:
	status_label.text = "Lifecycle regression: 8 concurrent workers"
	for iteration in 32:
		var nodes: Array[Node] = []
		for i in 8:
			var node: Variant = new_node("worker")
			node.animation_path = path_a
			node.play()
			nodes.append(node)
		await frames(1)
		for node in nodes:
			node.set("animation_path", path_b)
			node.set("animation_path", "")
			node.set("animation_path", path_zip)
		for node in nodes:
			node.queue_free()
		await frames(2)
		check_balanced("concurrent workers " + str(iteration))
	case_results["concurrent_workers"] = {"iterations": 32, "concurrent_nodes": 8, "counts": counts(), "passed": failures == 0}
	print("LIFECYCLE concurrent_workers ", "PASS" if failures == 0 else "FAIL", " ", counts())

func _ready() -> void:
	status_label = Label.new()
	status_label.position = Vector2(12, 12)
	status_label.add_theme_font_size_override("font_size", 18)
	status_label.text = "Lifecycle regression: packed PNG playback"
	add_child(status_label)
	write_text("user://lifecycle_result.json", JSON.stringify({"passed": false, "status": "running", "platform": OS.get_name()}))
	if not ClassDB.class_has_method("LottieAnimation", "debug_lifecycle_counts"):
		push_error("Build extension with lottie_lifecycle_tests=yes first")
		get_tree().quit(1)
		return
	# Keep PNG decoding in the lifecycle coverage, including dotLottie extraction.
	var blue_text := FileAccess.get_file_as_string("res://tests/fixtures/packed_bitmap.json")
	# Preserve integer-valued Lottie type tags. JSON.parse_string turns numbers
	# into floats; serializing ty=2.0 makes this ThorVG version misparse layers.
	blue_text = blue_text.replace('"o":{"a":1,"k":[{"t":0,"s":[0],"h":1},{"t":15,"s":[100]}]}', '"o":{"a":0,"k":100}')
	write_text(path_a, blue_text)
	write_text(path_b, '{"v":"5.7.4","fr":30,"ip":0,"op":90,"w":480,"h":320,"assets":[],"layers":[{"ty":1,"ind":1,"ip":0,"op":90,"sc":"#ff0000","sw":480,"sh":320,"ks":{"o":{"a":0,"k":100},"p":{"a":0,"k":[0,0,0]},"a":{"a":0,"k":[0,0,0]},"s":{"a":0,"k":[100,100,100]},"r":{"a":0,"k":0}}}]}')
	write_text(bad_json, "invalid json")
	write_text(bad_zip, "invalid zip")
	var pack := ZIPPacker.new()
	check(pack.open(path_zip) == OK, "could not create dotLottie fixture")
	pack.start_file("animations/animation_0.json")
	pack.write_file(blue_text.to_utf8_buffer())
	pack.close_file()
	pack.close()
	viewport = SubViewport.new()
	viewport.size = Vector2i(32, 32)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	await packed_playback()
	var modes := ["sync", "3d"] if OS.has_feature("web") else ["sync", "worker", "3d"]
	if OS.has_feature("web"):
		case_results["worker"] = {"skipped": true, "reason": "The addon worker is disabled on Web in production"}
	for kind in modes:
		await exercise(kind)
	if not OS.has_feature("web"):
		await concurrent_workers()
	print("LIFECYCLE_TEST ", "PASS" if failures == 0 else "FAIL", " ", counts())
	var report := {
		"platform": OS.get_name(), "device": OS.get_model_name(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"driver": RenderingServer.get_current_rendering_driver_name(),
		"passed": failures == 0, "status": "completed", "failures": failure_messages,
		"counts": counts(), "cases": case_results,
	}
	write_text("user://lifecycle_result.json", JSON.stringify(report, "  "))
	print("LIFECYCLE_REPORT ", JSON.stringify(report))
	status_label.text = "LIFECYCLE TEST " + ("PASS" if failures == 0 else "FAIL") + "\n" + OS.get_name() + " / " + report.renderer + " / " + report.driver + "\nCreated: " + str(report.counts.created) + "\nDestroyed: " + str(report.counts.destroyed) + "\nUnexpected Picture refs: " + str(report.counts.unexpected_picture_refs) + "\nRemaining workers: " + str(report.counts.workers)
	await RenderingServer.frame_post_draw
	get_tree().quit(0 if failures == 0 else 1)
