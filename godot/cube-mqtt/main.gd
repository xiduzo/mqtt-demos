## Main2D Script
## Connects MQTTClient signals to RotationController and initiates broker connection.
## Requirements: 4.1
extends Node2D

## Reference to the RotationController node
@onready var rotation_controller: RotationController = $RotationController


func _ready() -> void:
	# Connect MQTTClient.rotation_received signal to RotationController.apply_rotation
	MQTTClient.rotation_received.connect(rotation_controller.apply_rotation)
	
	# Initiate connection to the MQTT broker
	MQTTClient.connect_to_broker()
