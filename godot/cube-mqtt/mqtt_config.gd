## MQTTConfig Resource
## Configuration resource for MQTT client settings.
## Provides configurable broker address, port, and topic settings.
## Requirements: 5.1, 2.5
class_name MQTTConfig
extends Resource

## The WebSocket URL of the MQTT broker (must use wss:// for secure connection)
@export var broker_url: String = "wss://mqtt-public.xiduzo.com:443/mqtt"

## Unique client identifier for this MQTT connection
@export var client_id: String = "godot_cube_client"

## The MQTT topic to subscribe to for rotation messages
@export var rotation_topic: String = "cube/rotation/rotation"

## Delay in seconds before attempting to reconnect after a connection failure
@export var reconnect_delay: float = 5.0

## Default rotation mode: "absolute" sets rotation directly, "relative" adds to current rotation
@export var default_rotation_mode: String = "absolute"
