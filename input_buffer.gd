class_name InputBuffer

var _previous_buffered_events: Array[InputEvent] = []
var _buffered_events: Array[InputEvent] = []

# This is a bit of a weird attempt of getting a controllable input state
# to query mapped actions just like with the Input singleton.
# Events are buffered after received from push_event
# and keep existing until a released event is received.

func push_event(event: InputEvent) -> void:
	# Filter out old pressed
	if (event.is_released()):
		_buffered_events = _buffered_events.filter(
			func(existing_event): return !event.is_match(existing_event))
	
	_buffered_events.push_back(event)

func clear() -> void:
	_previous_buffered_events.clear()
	_buffered_events.clear()
	
func update() -> void:
	_previous_buffered_events.clear()
	_previous_buffered_events.append_array(_buffered_events)
	_buffered_events = _buffered_events.filter(
		func(event): return event.is_pressed())

func is_action_pressed(action: StringName, exact_match: bool = false) -> bool:
	return _buffered_events.any(func(event): return _is_action_pressed(event, action, exact_match))

func is_action_just_pressed(action: StringName, exact_match: bool = false) -> bool:
	var currently_pressed = is_action_pressed(action, exact_match)
	var previously_pressed = _previous_buffered_events.any(
		func(event): return _is_action_pressed(event, action, exact_match))
	
	return currently_pressed and !previously_pressed

func is_action_just_released(action: StringName, exact_match: bool = false) -> bool:
	return _buffered_events.any(func(event): return _is_action_just_released(event, action, exact_match))

func get_vector(negative_x: StringName, positive_x: StringName, negative_y: StringName, positive_y: StringName) -> Vector2:	
	return Vector2(
		get_action_strength(positive_x) - get_action_strength(negative_x),
		get_action_strength(positive_y) - get_action_strength(negative_y)
	)
	
func get_action_strength(action: StringName) -> float:
	var action_was_buffered = _buffered_events.any(func(event): return event.is_action(action))
	return Input.get_action_strength(action) if action_was_buffered else 0.0

func _is_action_pressed(event: InputEvent, action: StringName, exact_match: bool) -> bool:
	return event.is_action_pressed(action, false, exact_match)
	
func _is_action_just_released(event: InputEvent, action: StringName, exact_match: bool) -> bool:
	return event.is_action_just_released(action, exact_match)
