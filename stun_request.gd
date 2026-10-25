class_name StunRequest
extends Node

var _stun_address: String
var _stun_port: int

static var RESULT_ADDRESS = 0
static var RESULT_PORT = 1

const MAGIC_COOKIE: int = 0x2112A442
const XOR_MAPPED_ADDRESS: int = 0x0020
const MAPPED_ADDRESS: int = 0x0001
const BINDING_REQUEST: int = 0x0001

signal resolved(address: String, port: int)

func _init(stun_address: String, port: int):
	_stun_address = stun_address
	_stun_port = port

func request_for_port(port: int) -> Variant:
	var udp = PacketPeerUDP.new()
	
	var udp_status = udp.bind(port, '0.0.0.0')
	if (udp_status != OK):
		return udp_status
	
	udp.set_dest_address(_stun_address, _stun_port)
	
	var transaction_id = PackedByteArray()
	for n in 12:
		transaction_id.append(randi_range(0,255))

	var message = StreamPeerBuffer.new()
	message.big_endian = true
	message.put_u16(BINDING_REQUEST)
	message.put_u16(0x0000)
	message.put_u32(MAGIC_COOKIE)
	message.put_data(transaction_id)
	
	var put_result = udp.put_packet(message.data_array)
	if (put_result != OK):
		return put_result
	
	var timeout = Time.get_ticks_msec() + 5000
	
	while (udp.get_available_packet_count() == 0):
		if Time.get_ticks_msec() > timeout:
			push_error('Stun failed')
			return ERR_TIMEOUT
		
		await get_tree().create_timer(0.1).timeout

	var response = udp.get_packet()
	
	return _parse_stun_response(response)

func _parse_stun_response(raw_response: PackedByteArray) -> Variant:
	print("Response type: ", raw_response.decode_u16(0))
	print("Message length: ", raw_response.decode_u16(2))
	print("Magic cookie: ", raw_response.slice(4, 8).hex_encode())
	print("Transaction ID: ", raw_response.slice(8, 20).hex_encode())
	print("Attributes: ", raw_response.slice(20).hex_encode())
	
	var response = StreamPeerBuffer.new()
	response.data_array = raw_response
	response.big_endian = true
	var response_size = raw_response.size()
	
	if response_size < 20:
		push_error('STUN packet too short')
		return ERR_INVALID_DATA
	
	response.seek(0)
	var response_type = response.get_u16()
	if response_type != 0x0101:
		push_error('Not a Binding Success Response')
		return ERR_INVALID_DATA
	
	response.seek(4)
	var magic_cookie = response.get_u32()
	if magic_cookie != MAGIC_COOKIE:
		push_error('Invalid STUN magic cookie')
		return ERR_INVALID_DATA
	
	response.seek(2)
	var message_length: int = response.get_u16()
	var end: int = 20 + message_length
	
	if message_length % 4 != 0 or end > response_size:
		push_error('Invalid STUN message length')
		return ERR_INVALID_DATA
	
	var offset: int = 20
	var address = ''
	var port = 0
	
	while offset < end:
		
		if offset + 4 > end:
			push_error('Truncated attribute header')
			return ERR_INVALID_DATA
		
		response.seek(offset)
		var attr_type: int = response.get_u16()
		response.seek(offset + 2)
		var attr_length: int = response.get_u16()
		var value_offset: int = offset + 4
		
		if value_offset + attr_length > end:
			push_error('Invalid attribute length')
			return ERR_INVALID_DATA
		
		if attr_type != XOR_MAPPED_ADDRESS and attr_type != MAPPED_ADDRESS:
			offset += 4 + ((attr_length + 3) & ~3)
			continue
		
		if attr_length < 4:
			push_error('Address attribute too short')
			return ERR_INVALID_DATA
			
		response.seek(value_offset + 1)
		var family = response.get_u8()
		if family != 0x01:
			offset += 4 + ((attr_length + 3) & ~3)
			continue
			
		if attr_length != 8:
			push_error('Invalid IPv4 address attribute length')
			return ERR_INVALID_DATA
			
		var is_xor: bool = attr_type == XOR_MAPPED_ADDRESS
			
		response.seek(value_offset + 2)
		port = response.get_u16()
		if is_xor:
			port ^= 0x2112
			
		var parts: Array[String] = []
		for i in range(4):
			
			response.seek(value_offset + 4 + i)
			var octet = response.get_u8()
			if is_xor:
				octet ^= (MAGIC_COOKIE >> (24 - i * 8)) & 0xff
			parts.append(str(octet))
			
			address = '.'.join(parts)
			
		if is_xor:
			call_deferred('_emit_resolved', address, port)
			return OK
	
	if address.is_empty():
		return ERR_INVALID_DATA
	
	call_deferred('_emit_resolved', address, port)
	
	return OK

func _emit_resolved(address: String, port: int) -> void:
	resolved.emit(address, port)
