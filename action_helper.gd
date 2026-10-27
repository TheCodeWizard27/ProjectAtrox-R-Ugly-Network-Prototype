class_name ActionHelper

static var _event_filter: Array[String] = [
	'move_right',
	'move_left',
	'move_backward',
	'move_forward',
	'jump'
]

static func convert_to_actions(event: InputEvent) -> Array[InputEventAction]:
	var array: Array[InputEventAction] = []
	
	for action in _event_filter:
		
		if (!event.is_action(action)):
			continue
		
		var new_action = InputEventAction.new()
		new_action.action = action
		new_action.pressed = event.is_pressed()
		new_action.strength = 1 #event.get_action_strength(action)
		array.push_back(new_action)
	
	return array
