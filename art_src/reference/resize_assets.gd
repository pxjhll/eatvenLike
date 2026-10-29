extends SceneTree
## Mechanical texture downsampling only. Jobs are written by tools/optimize_reference_art.py.


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() == 1, "expected a resize-job JSON file")
	var jobs: Array = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	for job in jobs:
		var image := Image.load_from_file(ProjectSettings.globalize_path(job.path))
		assert(image != null and not image.is_empty(), "cannot read " + job.path)
		assert(job.width <= image.get_width() and job.height <= image.get_height(), "never upscale")
		image.resize(int(job.width), int(job.height), Image.INTERPOLATE_LANCZOS)
		assert(image.save_png(job.path) == OK, "cannot save " + job.path)
	print("Downsampled %d PNG textures" % jobs.size())
	quit()
