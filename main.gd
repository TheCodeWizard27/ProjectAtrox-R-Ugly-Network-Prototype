extends Node3D

const RESPONSE_BODY = 3

var _url = '83.78.19.253:7213'
var _http_url = 'https://' + _url
var _ws_url = 'wss://' + _url
var _socket: WebSocketPeer = WebSocketPeer.new()
var _port = 7777
var _stun_host = 'stun.l.google.com'
var _stun_port = 19302
var _json_header = 'Content-Type: application/json'

var _my_public_ip: String

var _is_host: bool = false
var _is_hole_alive: bool = false
var _is_connected: bool = false
var _peer_map: Dictionary[int, Player] = {}

@onready var _my_player: Player = $Player
@onready var _control: Control = $Control

func _process(_delta: float) -> void:
	_socket.poll()
	
	var state = _socket.get_ready_state()
	
	#if (_is_hole_alive and multiplayer.is_server()):
		#if (multiplayer.multiplayer_peer.get_available_packet_count()):
			#var test = multiplayer.multiplayer_peer.get_packet()
			#print('received packet: ', test.get_string_from_utf8())
		#
		#pass
	
	if (state != WebSocketPeer.STATE_OPEN):
		
		var missing_count = _socket.get_available_packet_count()
		if (missing_count):
			print('missed ', missing_count, ' packages')
		
		return
	
	while _socket.get_available_packet_count():
		var packet = _socket.get_packet()
		
		var packet_content = packet.get_string_from_utf8()
		var content = JSON.parse_string(packet_content)
		
		print(content)
		
		var type = content['Type'] 
		if (type != 0):
			continue
		
		var ip = content['Data']['PublicIp']
		var port = content['Data']['PublicPort']
		var local_ip = content['Data']['LocalIp']
		var local_port = content['Data']['LocalPort']
		
		print('starting hole punching')
		
		var target_ip = local_ip if ip == _my_public_ip else ip
		var target_port = local_port if ip == _my_public_ip else port
		
		if (_is_host):
			await _connect_to_peer_as_host(target_ip, target_port)
		else:
			await _connect_to_peer(target_ip, target_port)

func _start_hosting() -> void:
	var peer = ENetMultiplayerPeer.new()
	var result = peer.create_server(_port, 4)
	if (result != OK):
		push_error('Couldnt start server: ', result)
		return
	
	multiplayer.multiplayer_peer = peer
	var scene_multiplayer = multiplayer as SceneMultiplayer
	scene_multiplayer.peer_packet.connect(_on_packet_received)
	scene_multiplayer.peer_connected.connect(_on_peer_joined)
	_set_connected()
	print('Connected on Godot Level')

func _join_host(ip: String, port: int) -> void:
	var peer = ENetMultiplayerPeer.new()
	var result = peer.create_client(ip, port)
	if (result != OK):
		push_error('Couldnt join host: ', result)
		return
	
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_set_connected)
	print('Connected on Godot Level')

func _on_create_lobby_pressed() -> void:
	var request = HTTPRequest.new()
	add_child(request)
	var address = await get_address()
	var url = _http_url + '/Lobby/CreateHostLobbyConnection'
	var data = JSON.stringify({
		'Name': 'Test Lobby',
		'PublicIp': address.ip,
		'PublicPort': address.port,
		'LocalIp': address.local_ip,
		'LocalPort': address.local_port,
		'Password': null
	})
	var result = request.request(url, [_json_header], HTTPClient.METHOD_POST, data)
	
	if (result != OK):
		push_error(result)
		request.queue_free()
		return
	
	var response = await request.request_completed
	var body = response[RESPONSE_BODY] as PackedByteArray
	var connection_id = JSON.parse_string(body.get_string_from_utf8())
	_is_host = true
	print('Hosting ', connection_id)
	request.queue_free()
	_open_web_socket(connection_id)
	_start_hosting()

func _on_get_lobbies_pressed() -> void:
	var request = HTTPRequest.new()
	add_child(request)
	var result = request.request(_http_url + '/Lobby/Get')
	
	if (result != OK):
		push_error(result)
		request.queue_free()
		return
	
	var response = await request.request_completed
	var body = response[RESPONSE_BODY] as PackedByteArray
	var lobbies = JSON.parse_string(body.get_string_from_utf8()) as Array
	request.queue_free()
	_fill_lobbies(lobbies)

func _connect(lobby_id: String) -> void:
	var request = HTTPRequest.new()
	add_child(request)
	var address = await get_address()
	var url = _http_url + '/Lobby/CreateJoinLobbyConnection'
	var data = JSON.stringify({
		'LobbyId': lobby_id,
		'PublicIp': address.ip,
		'PublicPort': address.port,
		'LocalIp': address.local_ip,
		'LocalPort': address.local_port,
		'Password': null
	})
	var result = request.request(url, [_json_header], HTTPClient.METHOD_POST, data)
	if (result != OK):
		push_error(result)
		request.queue_free()
		return
	
	var response = await request.request_completed
	var body = response[RESPONSE_BODY] as PackedByteArray
	var connection_id = JSON.parse_string(body.get_string_from_utf8())
	print('Joining ', connection_id)
	request.queue_free()
	_open_web_socket(connection_id)

func _open_web_socket(connection_id: String):
	var url = _ws_url + '/Lobby/ConnectToWebSocket' + '?connectionId=' + connection_id
	_socket.heartbeat_interval = 0.5
	var result = _socket.connect_to_url(url)
	
	if (result != OK):
		push_error(result)

func _fill_lobbies(lobbies: Array) -> void:
	var button_control = $Control/HBoxContainer/LobbyButtons
	
	for child in button_control.get_children():
		button_control.remove_child(child)
	
	for lobby in lobbies:
		var button = Button.new()
		button.text = lobby['name'] + ' | ' + str(lobby['playerCount'])
		button.pressed.connect(_connect.bind(lobby['id']))
		button_control.add_child(button)

func _on_button_pressed() -> void:
	var address = await get_address()
	var test = IpHelper.get_local_ip()
	print(test)
	print(address.ip, ':', address.port)

func get_address() -> AddressInfo:
	var stun_ip = IP.resolve_hostname(_stun_host, IP.TYPE_IPV4)
	var stun_request = StunRequest.new(stun_ip, _stun_port)
	add_child(stun_request)
	
	var result = await stun_request.request_for_port(_port)
	if (result != OK):
		push_error(result)
		return
	
	var response = await stun_request.resolved
	var ip = response[StunRequest.RESULT_ADDRESS]
	var port = response[StunRequest.RESULT_PORT]
	
	var local_ip = IpHelper.get_local_ip()
	
	_my_public_ip = ip
	return AddressInfo.new(ip, port, local_ip, _port)

func _connect_to_peer_as_host(ip: String, port: int) -> void:
	var enet_peer = multiplayer.multiplayer_peer as ENetMultiplayerPeer
	var connection = enet_peer.host
	
	for i in range(50):
		print('trying to connect as host')
		
		connection.socket_send(ip, port, 'ping'.to_utf8_buffer())
		await get_tree().create_timer(0.3).timeout
		
		for peer_id in multiplayer.get_peers():
			var other_peer = enet_peer.get_peer(peer_id)
			var peer_ip = other_peer.get_remote_address()
			var peer_port = other_peer.get_remote_port()
			
			if (ip == peer_ip and port == peer_port):
				print('Stopping hole punching')
				return

func _connect_to_peer(ip: String, port: int) -> void:
	var udp = PacketPeerUDP.new()
	udp.set_dest_address(ip, port)
	var udp_status = udp.bind(_port, '0.0.0.0')
	if (udp_status != OK):
		push_error(udp_status)
		return
	
	var connection = false
	
	for i in range(50):
		print('trying to connect')
		
		udp.put_packet('ping'.to_utf8_buffer())
		await get_tree().create_timer(0.3).timeout
		
		if udp.get_available_packet_count() > 0:
			var packet = udp.get_packet()
			var parsed_packet = packet.get_string_from_utf8()
			
			if (parsed_packet.begins_with('ping')):
				udp.put_packet('ping'.to_utf8_buffer())
				udp.close()
				
				print('connected')
				_set_hole_punched()
				_join_host(ip, port)
				return
	
	if (!connection):
		push_error('could not connect...')
	
	udp.close()

func _input(event: InputEvent) -> void:
	_my_player.input_buffer.push_event(event)
	
	if(event is InputEventMouseMotion or event is InputEventMouseButton):
		return
	
	if (_is_connected and !multiplayer.is_server()):
		var scene_multiplayer = multiplayer as SceneMultiplayer
		
		for action in ActionHelper.convert_to_actions(event):
			var packet = JSON.stringify({
				'action': action.action,
				'pressed': action.pressed,
				'strength': action.strength
			}).to_utf8_buffer()
			#var packet = var_to_bytes(event)
			scene_multiplayer.send_bytes(packet)

func _set_hole_punched() -> void:
	_is_hole_alive = true

func _set_connected() -> void:
	_is_connected = true
	_control.hide()
	print('Fully connected ', 'server' if multiplayer.is_server() else 'client')

func _on_peer_joined(peer_id: int) -> void:
	var player_scene = preload("res://player.tscn").instantiate()
	$OtherPlayers.add_child(player_scene)
	_peer_map.set(peer_id, player_scene)

func _on_packet_received(peer_id: int, packet: PackedByteArray) -> void:
	var event = JSON.parse_string(packet.get_string_from_utf8())
	var action = InputEventAction.new()
	action.action = event['action']
	action.strength = event['strength']
	action.pressed = event['pressed']
	#print('Received ', event)
	#var event = bytes_to_var(packet)
	var player = _peer_map.get(peer_id) as Player
	
	if (player):
		player.input_buffer.push_action(action)
		print('buffered ', action.action)
