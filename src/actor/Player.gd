tool
extends KinematicBody2D
class_name Player

onready var areas : Node2D = $Areas
onready var hit_area : Area2D = $Areas/HitArea
onready var collider_size : Vector2 = $CollisionShape2D.shape.extents

onready var anim : AnimationPlayer = $AnimationPlayer
onready var sprites := $Sprites
onready var spr_root := $Sprites/Root
onready var spr_body := $Sprites/Root/Body
var spr_easy := EaseMover.new()

onready var spr_hand_l := $Sprites/Hands/Left
onready var spr_hand_r := $Sprites/Hands/Right
onready var spr_hands := [spr_hand_l, spr_hand_r]

onready var audio_grab := $Audio/Grab
onready var audio_push := $Audio/Push
onready var audio_turn := $Audio/Turn
onready var audio_jump := $Audio/Jump
onready var audio_land := $Audio/Land
onready var audio_fallout := $Audio/FallOut
onready var audio_spike := $Audio/Spike
onready var audio_around := $Audio/Around

export var is_input := true
var joy := Vector2.ZERO
var joy_last := Vector2.ZERO
var joy_q := Vector2.ZERO
var joy_buffer := 0.1
var hold_x := 0.0
var hold_y := 0.0
var btn_jump := false
var btnp_jump := false
var hold_jump := 0.0
var jump_buffer := 0.3
var btn_push := false
var btnp_push := false

export var is_cam := true
export var dir := 0 setget set_dir

var is_move := true
var is_walk := true
var is_floor := false

var velocity := Vector2.ZERO
var dir_x := 1 setget set_dir_x
signal scale_x
var idle_dir := "idle"

var walk_speed := 350.0
var floor_accel := 12
var air_accel := 7

var is_jump := false
var has_jumped := true
var jump_height := 240.0 setget set_jump_height
var jump_time := 0.6 setget set_jump_time
var jump_minimum := 0.12
var jump_speed := 0.0
var jump_gravity := 0.0
var fall_gravity := 0.0
var jump_clock := 0.0
var air_clock := 0.0

var is_dead := false
var dead_clock := 0.0
var dead_time := 0.7

var turn_clock := 0.0
var turn_time := 0.2
var turn_from := 0.0
var turn_to := 0.0

var is_hold := false
var is_release := false
var box
var push_clock := 0.0
var push_time := 0.2
var push_from := Vector2.ZERO
var push_dir := 1

var hold_clock := 0.0
var hold_cooldown := 0.2

var is_goal := false
var goal
var goal_step := 0
var goal_times := [0.2, 0.3, 0.5]
var goal_easy := EaseMover.new()
var hand_positions := [Vector2.ZERO, Vector2.ZERO]
var goal_start := Vector2.ZERO
var goal_grab := Vector2.ZERO

var squish_from := Vector2.ONE
var squish_clock := 0.0
var squish_time := 0.5

var is_unpause := false
var unpause_tick := 0

var release_clock := 0.0
var release_time := 0.2

onready var colors := {"hair": [$Sprites/Root/Body/Hair], "skin": [$Sprites/Root/Body/Head, $Sprites/Hands],
"fit": [$Sprites/Root/Body/Fit], "eye": [$Sprites/Root/Body/Eyes]}
export(Array, Color) var palette := []
export var dye := {"hair": 0, "skin": 0, "fit": 0, "eye": 0} setget set_dye

onready var hair_back := $Sprites/Root/Body/Hair/Back
onready var hair_front := $Sprites/Root/Body/Hair/Front
export (Array, String, FILE) var hair_backs := []
export (Array, String, FILE) var hair_fronts := []

export var hairstyle_back := 0 setget set_hair_back
export var hairstyle_front := 0 setget set_hair_front

func _enter_tree():
	if Engine.editor_hint: return
	if get_parent() == Shared:
		Shared.player = self
	MenuPause.connect("closed", self, "unpause")
	UI.connect("dialog_closed", self, "unpause")
	Shared.connect("scene_changed", self, "scene")
	Wipe.connect("start", self, "wipe_start")
	get_tree().connect("physics_frame", self, "physics_frame")

func _ready():
	set_hair_back()
	set_hair_front()
	if Engine.editor_hint: return
	solve_jump()
	
	var l = anim.get_animation("idle").duplicate()
	for i in 3:
		l.bezier_track_set_key_value(2, i, -l.bezier_track_get_key_value(2, i))
	anim.add_animation("idle_left", l)

func wipe_start(arg):
	spr_easy.show = arg

func scene():
	# go to last door
	if is_instance_valid(Shared.door_in):
		var d = Shared.door_in
		position = d.position
		self.dir = d.dir
		sprites.rotation = turn_to
		turn_clock = turn_time
	
	velocity = Vector2.ZERO
	joy_last = Vector2.ZERO
	joy = Vector2.ZERO
	is_jump = true
	is_dead = false
	sprites.position = Vector2.ZERO
	
	# snap to floor
	var test = rot(Vector2.DOWN * 150)
	if test_move(transform, test):
		move_and_collide(test)
		is_floor = true
		anim.play(idle_dir)
	else:
		anim.play("jump")
	
	# face left or right
	randomize()
	self.dir_x = 1 if randf() > 0.5 else -1

func _physics_process(delta):
	if Engine.editor_hint: return
	
	sprites.modulate.a = spr_easy.count(delta)
	
	if is_dead:
		sprites.position += rot(velocity) * delta
		sprites.rotate(deg2rad(-dir_x * 240) * delta)
		velocity.y += fall_gravity * delta
		
		if dead_clock < dead_time:
			dead_clock += delta
			if dead_clock > dead_time:
				Cutscene.is_playing = false
				Shared.reset()
		
		return
	
	# input
	release_clock = max(release_clock - delta, 0)
	
	if is_input and !Cutscene.is_playing and !Wipe.is_wipe:
		joy_last = joy
		joy = Input.get_vector("left", "right", "up", "down")
		joy = Vector2(sign(joy.x), sign(joy.y))
		
		btnp_jump = Input.is_action_just_pressed("jump")
		btnp_push = Input.is_action_just_pressed("grab")
		
		# avoid jumping or grabbing when exiting menu
		if is_unpause:
			unpause_tick += 1
			if unpause_tick > 1 and (btnp_jump or btnp_push):
				is_unpause = false
		
		if !is_unpause:
			btn_jump = Input.is_action_pressed("jump") and release_clock == 0 and !UI.dialog_menu.is_open
			btn_push = Input.is_action_pressed("grab")
	
	# holding input
	hold_x = (hold_x + delta) if joy.x == joy_last.x and joy.x != 0 else 0.0
	hold_y = (hold_y + delta) if joy.y == joy_last.y and joy.y != 0 else 0.0
	hold_jump = (hold_jump + delta) if btn_jump else 0.0
	
	# pickup goal
	if is_goal and is_instance_valid(goal):
		var s = goal_easy.count(delta)
		
		var offset = Vector2(20, 20) * goal.sprites.scale
		var p1 = goal.to_global(offset * Vector2(-1, 1))
		var p2 = goal.to_global(offset)
		
		spr_hand_l.global_position = p1
		spr_hand_r.global_position = p2
		
		match goal_step:
			0:
				spr_hand_l.global_position = hand_positions[0].linear_interpolate(p1, s)
				spr_hand_r.global_position = hand_positions[1].linear_interpolate(p2, s)
				
				move(goal_start.linear_interpolate(goal_grab, s) - position, 0)
			1:
				goal.position = goal_grab.linear_interpolate(position + rot(Vector2(0, -100)), s)
			
		# next step
		if goal_easy.is_complete:
			goal_easy.clock = 0.0
			goal_step += 1
			
			if goal_step < goal_times.size():
				goal_easy.time = goal_times[goal_step]
			
			if goal_step == 2:
				goal.shine(false)
			# finished
			elif goal_step > 2:
				is_goal = false
				is_floor = false
				has_jumped = true
				release_anim()
				
				goal.z_index = 0
				goal.target = self
	
	# holding box
	elif is_hold:
		
		if !is_release:
			# joy queue
			if joy.x != 0 and hold_x < joy_buffer:
				joy_q.x = joy.x
				hold_x = 1
			elif joy.y != 0 and hold_y < joy_buffer:
				joy_q.y = joy.y
				hold_y = 1
			
			# during push
			if push_clock < push_time:
				push_clock = min(push_clock + delta, push_time)
				
				var hold_pos = box.position + rot(Vector2(88 * -dir_x, 50 - collider_size.y))
				var smooth = smoothstep(0, 1, push_clock / push_time)
				var move_to = push_from.linear_interpolate(hold_pos, smooth)
				var diff = move_to - position
				
				move(diff, 0)
				
				# wobble body
				spr_root.rotation = lerp_angle(deg2rad(12 * -push_dir), 0, abs(0.5 - smooth) * 2.0)
			
			# during box turn
			elif box.is_turn:
				pass
			
			# not pushing or turning
			else:
				# check floor
				is_floor = test_move(transform, rot(Vector2.DOWN * 50))
				if !is_floor:
					walk_around(push_dir == 1)
					is_release = true
				
				# check distance
				elif position.distance_to(box.position) > 125:
					is_release = true
				
				# release button
				elif !btn_push:
					is_release = true
				
				# push / pull
				elif box.can_push and joy_q.x != 0:
					if dir_x == joy_q.x or !box.test_tile(dir - joy_q.x, 2):
						if box.start_push(dir - joy_q.x, joy_q.x):
							push_from = position
							push_clock = 0
							push_dir = joy_q.x
							
							audio_push.pitch_scale = rand_range(0.7, 1.3)
							audio_push.play()
							#print("push successful")
						#else:
						#	print("push failed")
				
				# turn box
				elif box.can_spin and joy_q.y != 0:
					box.dir += joy_q.y * -dir_x
					
					audio_turn.pitch_scale = rand_range(0.9, 1.3)
					audio_turn.play()
				
				joy_q = Vector2.ZERO
		
		# release box
		if is_release:
			box_release()
	
	# not holding
	else:
		# turning
		if turn_clock < turn_time:
			turn_clock = min(turn_clock + delta, turn_time)
			sprites.rotation = lerp_angle(turn_from, turn_to, smoothstep(0, 1, turn_clock / turn_time))
		
		# in control
		else:
			# dir_x
			if joy.x != 0:
				self.dir_x = joy.x
			
			# walking
			if is_walk:
				var target = joy.x * walk_speed 
				var weight = floor_accel if is_floor else air_accel
				velocity.x = lerp(velocity.x, target, weight * delta)
			
			# on the floor
			if is_floor:
				
				# animation
				anim.play(idle_dir if joy.x == 0 else "walk")
				
				# hold cooldown
				if hold_clock < hold_cooldown:
					hold_clock = min(hold_clock + delta, hold_cooldown)
				
				# start jump
				if btn_jump and hold_jump < jump_buffer:
					is_floor = false
					anim.play("jump")
					if dir_x > 0:
						anim.advance(anim.current_animation_length / 2.0)
					
					is_jump = true
					has_jumped = true
					velocity.y = jump_speed
					jump_clock = 0.0
					
					audio_jump.pitch_scale = rand_range(0.9, 1.1)
					audio_jump.play()
					
					squish_from = Vector2(0.7, 1.3)
					squish_clock = 0.0
				
				# start hold
				elif btn_push and hold_clock == hold_cooldown:
					var hb = hit_area.get_overlapping_bodies()
					if hb.size() > 0 and hb[0].is_in_group("box") and hb[0].is_floor:
						box = hb[0]
						print(name, " holding: ", box.name)
						is_hold = true
						is_release = false
						is_move = false
						velocity = Vector2.ZERO
						
						add_collision_exception_with(box)
						box.add_collision_exception_with(self)
						box.is_hold = true
						box.pickup()
						
						# dir_x double check
						var check_x = sprites.to_local(box.global_position).x > 0
						self.dir_x = 1 if check_x else -1
						
						push_from = position
						push_clock = 0
						push_dir = dir_x
						
						Guide.set_box(box)
						
						# move box to first child
						var p = box.get_parent()
						p.move_child(box, 0)
						
						anim.stop()
						
						audio_grab.pitch_scale = rand_range(0.7, 1.3)
						audio_grab.play()
				
			# in the air
			else:
				
				# during jump
				if is_jump:
					jump_clock += delta
					if btn_jump:
						# keep jump gravity if bonk head on ceiling
						if velocity.y >= -1.0 and jump_clock > (jump_time / 2.0):
							is_jump = false
							#print("jump start: ", jump_start, " / jump end: ", position.y + velocity.y, " / distance: ", position.y - jump_start)
					# short jump
					elif jump_clock > jump_minimum:
						is_jump = false
						velocity.y *= 0.8
				
				# not jumping
				else:
					# spin
					if !has_jumped:
						walk_around(test_move(transform, rot(Vector2(-25, 25))))
						has_jumped = true
						is_floor = false
		
		# movement
		if is_move:
			# gravity
			velocity.y += (jump_gravity if is_jump else fall_gravity) * delta
			
			# move
			move(velocity * delta)
	
	# check boundary
	if !Wipe.is_wipe and Boundary.is_outside(global_position):
		print(name, " outside boundary")
		die()
	
	# air clock
	if is_floor:
		if air_clock > 0.4:
			audio_land.pitch_scale = rand_range(0.7, 1.1)
			audio_land.play()

			squish_from = Vector2(1.3, 0.7)
			squish_clock = 0.0

		air_clock = 0.0
	else:
		air_clock += delta
	
	# squash squish and stretch
	squish_clock = min(squish_clock + delta, squish_time)
	var s = smoothstep(0, 1, squish_clock / squish_time)
	sprites.scale = squish_from.linear_interpolate(Vector2.ONE, s)

func physics_frame():
	# hold animation
	if is_hold:
		# hands
		var box_angle = turn_to
		var smooth = 0.2
		if box.is_turn or box.is_push:
			box_angle += box.sprite.rotation - (box.turn_from if box.is_turn else box.turn_to)
			smooth = 1.0
		
		var box_edge = box.sprite.global_position - Vector2(50 * dir_x, 0).rotated(box_angle)
		# move hands
		for i in 2:
			var offset = Vector2(0, 20  * (-1 if sign(dir_x + 1) == i else 1))
			var goto = box_edge + offset.rotated(box_angle)
			spr_hands[i].global_position = spr_hands[i].global_position.linear_interpolate(goto, smooth)
		
		# body
		spr_body.rotation = lerp_angle(spr_body.rotation, 0, 0.1)
		spr_body.position.y = lerp(spr_body.position.y, 0, 0.1)

### Set Get

func set_dir(arg := dir):
	dir = posmod(arg, 4)
	turn_to = deg2rad(dir * 90)
	
	turn_clock = 0
	turn_from = sprites.rotation if sprites else 0
	
	if Engine.editor_hint:
		$Sprites.rotation = turn_to
	elif Cam.target_node == self:
		Cam.turn(turn_to)
	
	if areas:
		areas.rotation = turn_to

func set_dir_x(arg := dir_x):
	dir_x = sign(arg)
	areas.scale.x = dir_x
	idle_dir = "idle" if dir_x > 0 else "idle_left"
	anim.playback_speed = dir_x
	emit_signal("scale_x", dir_x)

func set_jump_height(arg):
	jump_height = arg
	solve_jump()

func set_jump_time(arg):
	jump_time = arg
	solve_jump()

# Sebastian Lague's formula
func solve_jump():
	jump_gravity = (2 * jump_height) / pow(jump_time, 2)
	jump_speed = -jump_gravity * jump_time
	fall_gravity = jump_gravity * 2.0

func set_dye(arg):
	dye = arg
	for i in dye.keys():
		dye[i] = posmod(dye[i], palette.size())
		
		if colors and colors.has(i):
			for y in colors[i]:
				y.modulate = palette[dye[i]]

func set_hair_back(arg := hairstyle_back):
	hairstyle_back = posmod(arg, hair_backs.size())
	
	if hair_back:
		for i in hair_back.get_children():
			i.queue_free()
		
		if hairstyle_back > 0:
			var h = load(hair_backs[hairstyle_back]).instance()
			hair_back.add_child(h)
			for i in h.get_children():
				connect("scale_x", i, "scale_x")

func set_hair_front(arg := hairstyle_front):
	hairstyle_front = posmod(arg, hair_fronts.size())
	
	if hair_front:
		for i in hair_front.get_children():
			i.queue_free()
		
		if hairstyle_front > 0:
			var h = load(hair_fronts[hairstyle_front]).instance()
			hair_front.add_child(h)
			for i in h.get_children():
				connect("scale_x", i, "scale_x")

### Movement

func rot(vec : Vector2, _dir := dir) -> Vector2:
	_dir = posmod(_dir, 4)
	match _dir:
		1:
			return Vector2(-vec.y, vec.x)
		2:
			return Vector2(-vec.x, -vec.y)
		3:
			return Vector2(vec.y, -vec.x)
	
	return vec

func move(_vel := Vector2.ZERO, _dir := dir):
	# Move X
	var move_x = rot(_vel * Vector2(1, 0), _dir)
	var is_x = test_move(transform, move_x)
	move_and_collide(move_x)
	
	# Wall
	if is_x:
		velocity.x = 0.0
	
	# Move Y
	var move_y = rot(_vel * Vector2(0, 1), _dir)
	var is_y = test_move(transform, move_y)
	move_and_collide(move_y)
	
	if is_y:
		velocity.y = 0.0
	
	# Floor
	is_floor = is_y and _vel.y > 0
	if is_floor:
		velocity.y = 0
		has_jumped = false

func walk_around(right := false):
	move_and_collide(rot(Vector2.DOWN))
	self.dir += 1 if right else 3
	velocity.x = (walk_speed if right else -walk_speed) * 0.72
	
	audio_around.pitch_scale = rand_range(0.9, 1.3)
	audio_around.play()

### Area

func _on_BodyArea_area_entered(area):
	var p = area.get_parent()
	
	# pickup goal
	if !is_goal and p.is_in_group("goal") and !p.is_collected:
		area.set_deferred("monitorable", false)
		goal = p
		goal.is_collected = true
		goal.z_index = z_index + 1
		goal_grab = goal.position
		goal_start = position
		goal_step = 0
		goal_easy.time = goal_times[0]
		
		is_goal = true
		has_jumped = true
		is_floor = false
		velocity = Vector2.ZERO
		
		anim.stop()
		for i in spr_hands.size():
			hand_positions[i] = spr_hands[i].global_position
		Audio.play("gem_collect")

func _on_BodyArea_body_entered(body):
	if Wipe.is_wipe: return
	
	# hit spike
	if body.is_in_group("spike"):
		print("hit spike")
		die()

func die():
	if is_dead: return
	is_dead = true
	dead_clock = 0.0
	Cutscene.is_playing = true
	
	velocity = Vector2(-350 * dir_x, -800)
	if is_hold:
		box_release()
	anim.play("jump")
	
	audio_spike.play()
	audio_fallout.play()

func box_release():
	is_hold = false
	is_release = false
	is_move = true
	has_jumped = true
	hold_clock = 0.0
	spr_root.rotation = 0
	
	remove_collision_exception_with(box)
	box.remove_collision_exception_with(self)
	box.is_hold = false
	box.pickup()
	
	Guide.set_box(null)
	
	release_anim()
	
	audio_grab.pitch_scale = rand_range(0.7, 1.3)
	audio_grab.play()
	
	release_clock = release_time

func release_anim():
	# set animation keys
	var rel = anim.get_animation("release")
	
	rel.bezier_track_set_key_value(0, 0, spr_body.position.x)
	rel.bezier_track_set_key_value(1, 0, spr_body.position.y)
	rel.bezier_track_set_key_value(2, 0, spr_body.rotation_degrees)
	
	var diff = spr_hand_l.position - spr_hand_r.position
	var is_left = (diff.x < 0) if abs(diff.x) > 1 else (diff.y > 0) == (dir_x > 0)
	var lh = 3 if is_left else 5
	var rh = 5 if is_left else 3
	
	rel.bezier_track_set_key_value(lh, 0, spr_hand_l.position.x)
	rel.bezier_track_set_key_value(lh + 1, 0, spr_hand_l.position.y)
	rel.bezier_track_set_key_value(rh, 0, spr_hand_r.position.x)
	rel.bezier_track_set_key_value(rh + 1, 0, spr_hand_r.position.y)
	
	anim.play("release")

func enter_door():
	anim.play(idle_dir)
	joy = Vector2.ZERO

func unpause():
	print("unpause")
	unpause_tick = 0
	is_unpause = true
	btn_jump = false
	btn_push = false
