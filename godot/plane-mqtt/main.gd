## Main
## Wires MQTTClient.rotation_received to the PlaneController and connects to the broker.
extends Node3D

@onready var plane_controller: PlaneController = $PlaneController


func _ready() -> void:
	MQTTClient.rotation_received.connect(plane_controller.apply_rotation)
	MQTTClient.connect_to_broker()
