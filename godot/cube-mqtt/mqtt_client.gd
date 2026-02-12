## MQTTClient
## A GDScript-based MQTT client using Godot's WebSocketPeer for WSS communication.
## Handles connection management, subscription, and message reception for MQTT 3.1.1 protocol.
## Requirements: 2.1, 2.5, 5.1
## Note: class_name is intentionally omitted because this script is registered as an autoload singleton.
## The autoload name "MQTTClient" in project.godot provides the global reference.
extends Node

## Emitted when successfully connected to the MQTT broker
signal connected
## Emitted when disconnected from the MQTT broker
signal disconnected
## Emitted when any MQTT message is received (topic, payload)
signal message_received(topic: String, payload: String)
## Emitted when a rotation message is received and parsed
signal rotation_received(rotation_data: Dictionary)

# Configuration - can be set via exported variables or loaded from MQTTConfig resource
## The WebSocket URL of the MQTT broker (wss://)
@export var broker_url: String = "wss://mqtt-public.xiduzo.com:443/mqtt"
## Unique client identifier for this MQTT connection
@export var client_id: String = "godot_cube_client"
## The MQTT topic to subscribe to for rotation messages
@export var rotation_topic: String = "mobile/sensors/rotation"
## Delay in seconds before attempting to reconnect after a connection failure
@export var reconnect_delay: float = 5.0
## Optional MQTTConfig resource to load configuration from
@export var config: MQTTConfig

# Connection state
var _socket: WebSocketPeer
var _connected: bool = false
var _connecting: bool = false
var _awaiting_connack: bool = false

# Reconnection state
## Whether automatic reconnection is enabled
var _should_reconnect: bool = true
## Timer for scheduling reconnection attempts
var _reconnect_timer: SceneTreeTimer = null
## Whether a reconnection attempt is scheduled
var _reconnect_scheduled: bool = false

# Keepalive state
## Timer for sending PINGREQ packets
var _keepalive_timer: float = 0.0
## Interval in seconds between PINGREQ packets (half of keep-alive time)
const KEEPALIVE_INTERVAL: float = 30.0
## Whether we're waiting for a PINGRESP
var _awaiting_pingresp: bool = false
## Timeout for PINGRESP (seconds)
const PINGRESP_TIMEOUT: float = 10.0
## Time elapsed since last PINGREQ was sent
var _pingresp_wait_time: float = 0.0

# MQTT Protocol Constants
const MQTT_PROTOCOL_NAME: String = "MQTT"
const MQTT_PROTOCOL_VERSION: int = 4  # MQTT 3.1.1

# MQTT Packet Types (upper 4 bits of fixed header)
const PACKET_CONNECT: int = 0x10
const PACKET_CONNACK: int = 0x20
const PACKET_PUBLISH: int = 0x30
const PACKET_SUBSCRIBE: int = 0x80
const PACKET_SUBACK: int = 0x90
const PACKET_PINGREQ: int = 0xC0
const PACKET_PINGRESP: int = 0xD0
const PACKET_DISCONNECT: int = 0xE0

# CONNACK Return Codes
const CONNACK_ACCEPTED: int = 0x00
const CONNACK_REFUSED_PROTOCOL: int = 0x01
const CONNACK_REFUSED_IDENTIFIER: int = 0x02
const CONNACK_REFUSED_SERVER: int = 0x03
const CONNACK_REFUSED_CREDENTIALS: int = 0x04
const CONNACK_REFUSED_UNAUTHORIZED: int = 0x05


func _ready() -> void:
	_load_configuration()


## Handles Godot notifications for graceful shutdown.
## Requirements: 2.4
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			# Application window is being closed
			_log_info("Window close requested - disconnecting gracefully")
			_graceful_disconnect()
		NOTIFICATION_PREDELETE:
			# Node is about to be deleted
			_log_info("Node being deleted - disconnecting gracefully")
			_graceful_disconnect()


## Called when the node is removed from the scene tree.
## Ensures graceful disconnect from the broker.
## Requirements: 2.4
func _exit_tree() -> void:
	_log_info("Exiting scene tree - disconnecting gracefully")
	_graceful_disconnect()


## Performs a graceful disconnect, disabling reconnection.
## Requirements: 2.4
func _graceful_disconnect() -> void:
	# Disable reconnection to prevent reconnect attempts during shutdown
	_should_reconnect = false
	_cancel_reconnect()
	
	# Disconnect from broker
	if _connected or _connecting:
		disconnect_from_broker()


func _process(delta: float) -> void:
	if _connecting:
		_poll_connection()
	elif _awaiting_connack:
		_poll_for_connack()
	elif _connected:
		_process_incoming_data()
		_process_keepalive(delta)


## Loads configuration from MQTTConfig resource if available, otherwise uses defaults.
## Invalid configuration values are replaced with sensible defaults.
## Requirements: 5.1, 5.4
func _load_configuration() -> void:
	if config:
		# Load from resource, validating each value
		broker_url = _validate_url(config.broker_url)
		client_id = _validate_client_id(config.client_id)
		rotation_topic = _validate_topic(config.rotation_topic)
		reconnect_delay = _validate_reconnect_delay(config.reconnect_delay)
		_log_info("Configuration loaded from MQTTConfig resource")
	else:
		# Validate current exported values
		broker_url = _validate_url(broker_url)
		client_id = _validate_client_id(client_id)
		rotation_topic = _validate_topic(rotation_topic)
		reconnect_delay = _validate_reconnect_delay(reconnect_delay)
		_log_info("Using default/exported configuration")


## Validates broker URL, returns default if invalid.
## Requirements: 5.4
func _validate_url(url: String) -> String:
	if url.is_empty() or not url.begins_with("wss://"):
		_log_warning("Invalid broker URL, using default 'wss://mqtt-public.xiduzo.com:443/mqtt'")
		return "wss://mqtt-public.xiduzo.com:443/mqtt"
	return url


## Validates client ID, returns default if invalid.
## Requirements: 5.4
func _validate_client_id(id: String) -> String:
	if id.is_empty():
		_log_warning("Empty client ID, using default 'godot_cube_client'")
		return "godot_cube_client"
	return id


## Validates rotation topic, returns default if invalid.
## Requirements: 5.4
func _validate_topic(topic: String) -> String:
	if topic.is_empty():
		_log_warning("Empty rotation topic, using default 'cube/rotation/rotation'")
		return "cube/rotation/rotation"
	return topic


## Validates reconnect delay, returns default if invalid.
## Requirements: 5.4
func _validate_reconnect_delay(delay: float) -> float:
	if delay < 0.0:
		_log_warning("Invalid reconnect delay %.1f, using default 5.0" % delay)
		return 5.0
	return delay


## Attempts to connect to the configured MQTT broker over WSS.
## Returns OK on successful connection initiation, or an error code on failure.
## Requirements: 2.1
func connect_to_broker() -> Error:
	if _connected:
		_log_warning("Already connected to broker")
		return ERR_ALREADY_IN_USE
	
	if _connecting:
		_log_warning("Connection already in progress")
		return ERR_BUSY
	
	# Create new WebSocket peer
	_socket = WebSocketPeer.new()
	
	# Set supported protocols for MQTT over WebSocket
	_socket.supported_protocols = PackedStringArray(["mqtt"])
	
	# Configure TLS options for WSS
	var tls_options := TLSOptions.client()
	
	# Attempt to connect with TLS
	var err := _socket.connect_to_url(broker_url, tls_options)
	if err != OK:
		_log_error("Failed to initiate connection to %s - Error: %d" % [broker_url, err])
		_socket = null
		return err
	
	_connecting = true
	_log_info("Connecting to MQTT broker at %s..." % broker_url)
	return OK


## Polls the connection status during the connecting phase.
## Sends CONNECT packet once WebSocket connection is established.
func _poll_connection() -> void:
	if not _socket:
		_connecting = false
		return
	
	_socket.poll()
	var state := _socket.get_ready_state()
	
	match state:
		WebSocketPeer.STATE_OPEN:
			_connecting = false
			_log_info("WebSocket connection established, sending MQTT CONNECT packet")
			var err := _send_connect_packet()
			if err != OK:
				_log_error("Failed to send CONNECT packet")
				_handle_connection_failure()
			else:
				_awaiting_connack = true
		WebSocketPeer.STATE_CONNECTING:
			# Still connecting, wait
			pass
		WebSocketPeer.STATE_CLOSING, WebSocketPeer.STATE_CLOSED:
			_log_error("WebSocket connection failed")
			_connecting = false
			_handle_connection_failure()


## Polls for CONNACK response after sending CONNECT packet.
func _poll_for_connack() -> void:
	if not _socket:
		_awaiting_connack = false
		return
	
	_socket.poll()
	
	var state := _socket.get_ready_state()
	if state != WebSocketPeer.STATE_OPEN:
		_log_error("WebSocket closed while waiting for CONNACK")
		_awaiting_connack = false
		_handle_connection_failure()
		return
	
	# Check for incoming packets
	while _socket.get_available_packet_count() > 0:
		var bytes := _socket.get_packet()
		if bytes.size() > 0:
			_log_info("Received packet (%d bytes): %s" % [bytes.size(), bytes.hex_encode()])
			_handle_packet(bytes)


## Handles connection failure by cleaning up and scheduling reconnection.
## Requirements: 2.3
func _handle_connection_failure() -> void:
	if _socket:
		_socket.close()
		_socket = null
	_connected = false
	_connecting = false
	_awaiting_connack = false
	_reset_keepalive_state()
	disconnected.emit()
	
	# Schedule reconnection if enabled
	if _should_reconnect and not _reconnect_scheduled:
		_schedule_reconnect()


## Schedules a reconnection attempt after the configured delay.
## Requirements: 2.3
func _schedule_reconnect() -> void:
	if _reconnect_scheduled:
		return
	
	_reconnect_scheduled = true
	_log_info("Scheduling reconnection in %.1f seconds..." % reconnect_delay)
	
	# Use SceneTreeTimer for non-blocking delay
	_reconnect_timer = get_tree().create_timer(reconnect_delay)
	_reconnect_timer.timeout.connect(_on_reconnect_timeout)


## Called when the reconnection timer expires.
## Attempts to reconnect to the broker.
## Requirements: 2.3
func _on_reconnect_timeout() -> void:
	_reconnect_scheduled = false
	_reconnect_timer = null
	
	if not _should_reconnect:
		_log_info("Reconnection cancelled")
		return
	
	if _connected or _connecting:
		_log_info("Already connected or connecting, skipping reconnection")
		return
	
	_log_info("Attempting to reconnect...")
	var err := connect_to_broker()
	if err != OK:
		_log_error("Reconnection attempt failed: %d" % err)
		# Schedule another reconnection attempt
		if _should_reconnect:
			_schedule_reconnect()


## Cancels any scheduled reconnection attempt.
func _cancel_reconnect() -> void:
	_should_reconnect = false
	_reconnect_scheduled = false
	if _reconnect_timer and _reconnect_timer.time_left > 0:
		# Timer will still fire but _on_reconnect_timeout will check _should_reconnect
		pass
	_reconnect_timer = null


## Enables or disables automatic reconnection.
func set_auto_reconnect(enabled: bool) -> void:
	_should_reconnect = enabled
	if not enabled:
		_cancel_reconnect()


## Resets keepalive state variables.
func _reset_keepalive_state() -> void:
	_keepalive_timer = 0.0
	_awaiting_pingresp = false
	_pingresp_wait_time = 0.0


## Processes keepalive logic - sends PINGREQ and monitors for PINGRESP.
## Requirements: 2.3 (connection health monitoring)
func _process_keepalive(delta: float) -> void:
	if not _connected:
		return
	
	# If waiting for PINGRESP, check for timeout
	if _awaiting_pingresp:
		_pingresp_wait_time += delta
		if _pingresp_wait_time >= PINGRESP_TIMEOUT:
			_log_error("PINGRESP timeout - connection may be dead")
			_handle_connection_failure()
			return
	
	# Increment keepalive timer
	_keepalive_timer += delta
	
	# Send PINGREQ at regular intervals
	if _keepalive_timer >= KEEPALIVE_INTERVAL:
		_send_pingreq()
		_keepalive_timer = 0.0


## Sends an MQTT PINGREQ packet for keepalive.
func _send_pingreq() -> void:
	if not _socket or not _connected:
		return
	
	var packet := PackedByteArray()
	packet.append(PACKET_PINGREQ)  # 0xC0
	packet.append(0x00)            # Remaining length = 0
	
	var err := _socket.send(packet, WebSocketPeer.WRITE_MODE_BINARY)
	if err != OK:
		_log_error("Failed to send PINGREQ: %d" % err)
		_handle_connection_failure()
		return
	
	_awaiting_pingresp = true
	_pingresp_wait_time = 0.0
	_log_info("PINGREQ sent")


## Disconnects from the MQTT broker gracefully.
## Requirements: 2.4
func disconnect_from_broker() -> void:
	if not _connected and not _connecting:
		return
	
	# Cancel any pending reconnection
	_cancel_reconnect()
	
	if _connected and _socket:
		# Send DISCONNECT packet
		_send_disconnect_packet()
	
	if _socket:
		_socket.close()
		_socket = null
	
	_connected = false
	_connecting = false
	_reset_keepalive_state()
	_log_info("Disconnected from MQTT broker")
	disconnected.emit()


## Constructs and sends an MQTT 3.1.1 CONNECT packet.
## Returns OK on success, or an error code on failure.
func _send_connect_packet() -> Error:
	var packet := PackedByteArray()
	
	# Build variable header
	var variable_header := PackedByteArray()
	
	# Protocol Name (length-prefixed string "MQTT")
	variable_header.append_array(_encode_string(MQTT_PROTOCOL_NAME))
	
	# Protocol Version (4 for MQTT 3.1.1)
	variable_header.append(MQTT_PROTOCOL_VERSION)
	
	# Connect Flags
	# Bit 7: Username Flag = 0
	# Bit 6: Password Flag = 0
	# Bit 5: Will Retain = 0
	# Bit 4-3: Will QoS = 0
	# Bit 2: Will Flag = 0
	# Bit 1: Clean Session = 1
	# Bit 0: Reserved = 0
	var connect_flags: int = 0x02  # Clean Session only
	variable_header.append(connect_flags)
	
	# Keep Alive (60 seconds)
	var keep_alive: int = 60
	variable_header.append((keep_alive >> 8) & 0xFF)  # MSB
	variable_header.append(keep_alive & 0xFF)         # LSB
	
	# Build payload
	var payload := PackedByteArray()
	
	# Client Identifier (length-prefixed string)
	payload.append_array(_encode_string(client_id))
	
	# Calculate remaining length
	var remaining_length := variable_header.size() + payload.size()
	
	# Build fixed header
	packet.append(PACKET_CONNECT)
	packet.append_array(_encode_remaining_length(remaining_length))
	
	# Append variable header and payload
	packet.append_array(variable_header)
	packet.append_array(payload)
	
	# Send packet as binary
	_log_info("Sending CONNECT packet (%d bytes): %s" % [packet.size(), packet.hex_encode()])
	var err := _socket.send(packet, WebSocketPeer.WRITE_MODE_BINARY)
	if err != OK:
		_log_error("Failed to send CONNECT packet: %d" % err)
		return err
	
	_log_info("CONNECT packet sent, waiting for CONNACK...")
	return OK


## Sends an MQTT DISCONNECT packet.
func _send_disconnect_packet() -> void:
	if not _socket:
		return
	
	var packet := PackedByteArray()
	packet.append(PACKET_DISCONNECT)
	packet.append(0x00)  # Remaining length = 0
	
	_socket.send(packet, WebSocketPeer.WRITE_MODE_BINARY)


# Packet identifier counter for SUBSCRIBE packets
var _packet_id: int = 1


## Subscribes to an MQTT topic.
## Returns OK on success, or an error code on failure.
## Requirements: 2.2
func subscribe(topic: String) -> Error:
	if not _connected:
		_log_error("Cannot subscribe: not connected to broker")
		return ERR_CONNECTION_ERROR
	
	if not _socket:
		_log_error("Cannot subscribe: socket not available")
		return ERR_UNAVAILABLE
	
	if topic.is_empty():
		_log_error("Cannot subscribe: empty topic")
		return ERR_INVALID_PARAMETER
	
	# Build SUBSCRIBE packet
	var packet := PackedByteArray()
	
	# Variable header: Packet Identifier (2 bytes)
	var variable_header := PackedByteArray()
	variable_header.append((_packet_id >> 8) & 0xFF)  # MSB
	variable_header.append(_packet_id & 0xFF)         # LSB
	
	# Payload: Topic Filter (length-prefixed string) + QoS (1 byte)
	var payload := PackedByteArray()
	payload.append_array(_encode_string(topic))
	payload.append(0x00)  # QoS 0
	
	# Calculate remaining length
	var remaining_length := variable_header.size() + payload.size()
	
	# Fixed header: SUBSCRIBE packet type (0x82) + remaining length
	# 0x82 = 0x80 (SUBSCRIBE) | 0x02 (required flags for SUBSCRIBE)
	packet.append(0x82)
	packet.append_array(_encode_remaining_length(remaining_length))
	
	# Append variable header and payload
	packet.append_array(variable_header)
	packet.append_array(payload)
	
	# Send packet
	# Send packet as binary
	var err := _socket.send(packet, WebSocketPeer.WRITE_MODE_BINARY)
	if err != OK:
		_log_error("Failed to send SUBSCRIBE packet: %d" % err)
		return err
	
	_log_info("SUBSCRIBE packet sent for topic: %s (packet ID: %d)" % [topic, _packet_id])
	
	# Increment packet ID for next subscription
	_packet_id += 1
	if _packet_id > 65535:
		_packet_id = 1
	
	return OK


## Encodes a string as a length-prefixed byte array (MQTT string format).
func _encode_string(s: String) -> PackedByteArray:
	var result := PackedByteArray()
	var utf8 := s.to_utf8_buffer()
	var length := utf8.size()
	
	# Length prefix (2 bytes, big-endian)
	result.append((length >> 8) & 0xFF)
	result.append(length & 0xFF)
	
	# String data
	result.append_array(utf8)
	
	return result


## Encodes the remaining length field using MQTT variable-length encoding.
func _encode_remaining_length(length: int) -> PackedByteArray:
	var result := PackedByteArray()
	
	while true:
		var encoded_byte := length % 128
		length = length / 128
		
		if length > 0:
			encoded_byte = encoded_byte | 0x80
		
		result.append(encoded_byte)
		
		if length <= 0:
			break
	
	return result


## Decodes the remaining length field from MQTT variable-length encoding.
## Returns [remaining_length, bytes_consumed] or [-1, 0] on error.
func _decode_remaining_length(bytes: PackedByteArray, start_index: int) -> Array:
	var multiplier := 1
	var value := 0
	var index := start_index
	
	while index < bytes.size():
		var encoded_byte := bytes[index]
		value += (encoded_byte & 0x7F) * multiplier
		
		if multiplier > 128 * 128 * 128:
			# Malformed remaining length
			return [-1, 0]
		
		multiplier *= 128
		index += 1
		
		if (encoded_byte & 0x80) == 0:
			# This was the last byte
			return [value, index - start_index]
	
	# Incomplete remaining length encoding
	return [-1, 0]


## Parses a JSON rotation message payload and returns a rotation data dictionary.
## Returns {valid: false} for invalid JSON.
## Missing fields default to zero.
## Requirements: 3.1
func _parse_rotation_message(payload: String) -> Dictionary:
	var result: Dictionary = {
		"x": 0.0,
		"y": 0.0,
		"z": 0.0,
		"mode": "absolute",
		"valid": true
	}
	
	# Attempt to parse JSON
	var json := JSON.new()
	var parse_error := json.parse(payload)
	
	if parse_error != OK:
		_log_warning("Invalid JSON in rotation message: " + payload.substr(0, 50))
		return {"valid": false}
	
	var data = json.get_data()
	
	# Ensure we got a dictionary
	if not data is Dictionary:
		_log_warning("Rotation message is not a JSON object")
		return {"valid": false}
	
	# Extract and validate rotation values, using zero for missing/invalid fields
	result["x"] = _validate_rotation_value(data.get("x", 0.0))
	result["y"] = _validate_rotation_value(data.get("y", 0.0))
	result["z"] = _validate_rotation_value(data.get("z", 0.0))
	
	# Extract mode if present
	if data.has("mode") and data["mode"] is String:
		result["mode"] = data["mode"]
	
	return result


## Validates that a rotation value is numeric and returns it as a float.
## Returns 0.0 for non-numeric values.
func _validate_rotation_value(value: Variant) -> float:
	if value is float:
		return value
	elif value is int:
		return float(value)
	else:
		if value != null:
			_log_warning("Non-numeric rotation value: " + str(value))
		return 0.0


## Processes incoming data from the WebSocket.
## Handles CONNACK and other MQTT packet types.
func _process_incoming_data() -> void:
	if not _socket:
		return
	
	_socket.poll()
	
	# Check connection status
	var state := _socket.get_ready_state()
	if state != WebSocketPeer.STATE_OPEN:
		if _connected:
			_log_error("Connection lost (state: %d)" % state)
			_handle_connection_failure()
		return
	
	# Process all available packets
	var packet_count := _socket.get_available_packet_count()
	if packet_count > 0:
		_log_info("Received %d packet(s)" % packet_count)
	
	while _socket.get_available_packet_count() > 0:
		var bytes := _socket.get_packet()
		if bytes.size() > 0:
			_log_info("Received packet (%d bytes): %s" % [bytes.size(), bytes.hex_encode()])
			_handle_packet(bytes)


## Handles an incoming MQTT packet.
func _handle_packet(bytes: PackedByteArray) -> void:
	if bytes.size() < 2:
		return
	
	var packet_type := bytes[0] & 0xF0
	
	match packet_type:
		PACKET_CONNACK:
			_handle_connack(bytes)
		PACKET_SUBACK:
			_handle_suback(bytes)
		PACKET_PUBLISH:
			_handle_publish(bytes)
		PACKET_PINGRESP:
			_handle_pingresp()
		_:
			_log_warning("Unknown packet type: 0x%02X" % packet_type)


## Handles a CONNACK packet response.
## Requirements: 2.1, 2.2
func _handle_connack(bytes: PackedByteArray) -> void:
	_awaiting_connack = false
	
	if bytes.size() < 4:
		_log_error("CONNACK packet too short")
		_handle_connection_failure()
		return
	
	# bytes[0] = packet type (0x20)
	# bytes[1] = remaining length (should be 2)
	# bytes[2] = session present flag
	# bytes[3] = return code
	
	var return_code := bytes[3]
	
	if return_code == CONNACK_ACCEPTED:
		_connected = true
		_log_info("Connected to MQTT broker successfully")
		connected.emit()
		# Auto-subscribe to rotation topic after successful connection
		# Requirements: 2.2
		var err := subscribe(rotation_topic)
		if err != OK:
			_log_error("Failed to subscribe to rotation topic: %s" % rotation_topic)
	else:
		var reason := _get_connack_error_reason(return_code)
		_log_error("Connection refused: %s (code: %d)" % [reason, return_code])
		_handle_connection_failure()


## Returns a human-readable reason for a CONNACK error code.
func _get_connack_error_reason(code: int) -> String:
	match code:
		CONNACK_REFUSED_PROTOCOL:
			return "Unacceptable protocol version"
		CONNACK_REFUSED_IDENTIFIER:
			return "Identifier rejected"
		CONNACK_REFUSED_SERVER:
			return "Server unavailable"
		CONNACK_REFUSED_CREDENTIALS:
			return "Bad username or password"
		CONNACK_REFUSED_UNAUTHORIZED:
			return "Not authorized"
		_:
			return "Unknown error"


## Handles a SUBACK packet response.
## Requirements: 2.2
func _handle_suback(bytes: PackedByteArray) -> void:
	if bytes.size() < 5:
		_log_warning("SUBACK packet too short")
		return
	
	# bytes[0] = packet type (0x90)
	# bytes[1] = remaining length
	# bytes[2-3] = packet identifier (2 bytes, big-endian)
	# bytes[4+] = return codes (one per topic subscribed)
	
	var packet_id := (bytes[2] << 8) | bytes[3]
	var return_code := bytes[4]
	
	# Return codes: 0x00 = QoS 0, 0x01 = QoS 1, 0x02 = QoS 2, 0x80 = Failure
	if return_code == 0x80:
		_log_error("SUBACK: Subscription failed for packet ID %d" % packet_id)
	else:
		_log_info("SUBACK: Subscription successful (QoS %d) for packet ID %d" % [return_code, packet_id])


## Handles a PUBLISH packet (QoS 0).
## Extracts topic and payload, emits message_received and rotation_received signals.
## Requirements: 2.2, 3.1
func _handle_publish(bytes: PackedByteArray) -> void:
	if bytes.size() < 4:
		_log_warning("PUBLISH packet too short")
		return
	
	# bytes[0] = packet type (0x30 for QoS 0)
	# bytes[1+] = remaining length (variable length encoding)
	# Then: topic length (2 bytes) + topic + payload
	
	# Decode remaining length
	var remaining_length_result := _decode_remaining_length(bytes, 1)
	var remaining_length: int = remaining_length_result[0]
	var header_size: int = remaining_length_result[1]
	
	if remaining_length < 0:
		_log_warning("PUBLISH: Invalid remaining length encoding")
		return
	
	var offset := 1 + header_size  # Start of variable header
	
	# Extract topic length (2 bytes, big-endian)
	if bytes.size() < offset + 2:
		_log_warning("PUBLISH: Packet too short for topic length")
		return
	
	var topic_length := (bytes[offset] << 8) | bytes[offset + 1]
	offset += 2
	
	# Extract topic
	if bytes.size() < offset + topic_length:
		_log_warning("PUBLISH: Packet too short for topic")
		return
	
	var topic_bytes := bytes.slice(offset, offset + topic_length)
	var topic := topic_bytes.get_string_from_utf8()
	offset += topic_length
	
	# Extract payload (rest of the packet)
	var payload_bytes := bytes.slice(offset)
	var payload := payload_bytes.get_string_from_utf8()
	
	_log_info("PUBLISH received - Topic: %s, Payload: %s" % [topic, payload.substr(0, 100)])
	
	# Emit general message_received signal
	message_received.emit(topic, payload)
	
	# If this is the rotation topic, parse and emit rotation_received signal
	if topic == rotation_topic:
		var rotation_data := _parse_rotation_message(payload)
		if rotation_data.get("valid", false):
			rotation_received.emit(rotation_data)


## Handles a PINGRESP packet.
## Confirms the broker is alive and resets the keepalive wait state.
func _handle_pingresp() -> void:
	if _awaiting_pingresp:
		_awaiting_pingresp = false
		_pingresp_wait_time = 0.0
		_log_info("PINGRESP received - connection alive")


## Returns whether the client is currently connected to the broker.
func is_broker_connected() -> bool:
	return _connected


## Logging helpers
func _log_error(message: String) -> void:
	push_error("[MQTTClient] " + message)


func _log_warning(message: String) -> void:
	push_warning("[MQTTClient] " + message)


func _log_info(message: String) -> void:
	print("[MQTTClient] " + message)
