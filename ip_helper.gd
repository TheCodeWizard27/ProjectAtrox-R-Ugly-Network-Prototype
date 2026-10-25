class_name IpHelper

static func get_local_ip() -> String:
	var local_addresses = IP.get_local_addresses()
	
	for address in local_addresses:
		if (address.begins_with('192.168.') || address.begins_with('10.0.') || address.begins_with('172.16.')):
			return address
	
	return '127.0.0.1' # Should never occur but just return loopback for now.
