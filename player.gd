class_name Player
extends Node3D

@onready var body: CharacterBody3D = $CharacterBody3D
var input_buffer: ActionBuffer = ActionBuffer.new()

func _process_movement(delta: float) -> void:
	
	var label = $CharacterBody3D/Label3D
	label.text = ''
	
	if input_buffer.is_action_pressed('move_right'):
		label.text += '[mr]'
	if input_buffer.is_action_pressed('move_left'):
		label.text += '[ml]'
	if input_buffer.is_action_pressed('move_forward'):
		label.text += '[mf]'
	if input_buffer.is_action_pressed('move_backward'):
		label.text += '[mb]'
	if input_buffer.is_action_pressed('jump'):
		label.text += '[jmp]'
	
	var move_dir = Vector3.ZERO
	move_dir.x = input_buffer.get_action_strength('move_right') - input_buffer.get_action_strength('move_left')
	move_dir.z = input_buffer.get_action_strength('move_backward') - input_buffer.get_action_strength('move_forward')
	move_dir = move_dir.normalized()
	
	if (input_buffer.is_action_just_pressed('jump')):
		body.velocity.y = 5
	
	body.rotate(Vector3.UP, move_dir.x * delta * -5)
	
	move_dir = move_dir.rotated(Vector3.UP, body.rotation.y)
	
	var y_velocity = body.velocity.y
	body.velocity = move_dir * 10
	body.velocity.y = y_velocity - 9.81 * 2 * delta

func _physics_process(delta: float) -> void:
	_process_movement(delta)
	body.move_and_slide()
	input_buffer.update()
