extends Node2D

onready var logo := $Logo

func _ready():
	yield(get_tree().create_timer(1.0), "timeout")
	Shared.wipe_scene(Shared.scene_title)
