# Implementation Plan: 3D Cube in 2D Scene with MQTT-Controlled Rotation

## Overview

This implementation plan breaks down the feature into incremental coding tasks using GDScript for Godot 4.6. Each task builds on previous work, with property tests placed close to implementation to catch errors early.

## Tasks

- [x] 1. Set up project structure and scene hierarchy
  - [x] 1.1 Create the main 2D scene with SubViewport for 3D rendering
    - Create `main.tscn` with Node2D root
    - Add SubViewportContainer and SubViewport nodes
    - Configure SubViewport size (512x512) and update mode
    - Add Camera3D positioned at (0, 2, 5) looking at origin
    - Add DirectionalLight3D for cube illumination
    - Add MeshInstance3D with BoxMesh (2x2x2) and StandardMaterial3D
    - _Requirements: 1.1, 1.2, 1.4_

  - [x] 1.2 Create MQTTConfig resource class
    - Create `mqtt_config.gd` extending Resource
    - Add exported properties: broker_host, broker_port, client_id, rotation_topic, reconnect_delay
    - Set sensible defaults (localhost:1883, "cube/rotation")
    - _Requirements: 5.1, 2.5_

- [x] 2. Implement rotation message parsing and validation
  - [x] 2.1 Create RotationController with parsing logic
    - Create `rotation_controller.gd` extending Node
    - Implement `_parse_rotation_message(payload: String) -> Dictionary`
    - Implement `_validate_rotation_value(value: Variant) -> float`
    - Implement `_clamp_rotation(degrees: float) -> float`
    - Handle missing fields with zero defaults
    - Return `{valid: false}` for invalid JSON
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 4.4_

  - [ ]* 2.2 Write property test for JSON parsing round-trip
    - **Property 1: JSON Rotation Parsing Round-Trip**
    - **Validates: Requirements 3.1, 3.2**

  - [ ]* 2.3 Write property test for missing fields defaulting to zero
    - **Property 2: Missing Fields Default to Zero**
    - **Validates: Requirements 3.4**

  - [ ]* 2.4 Write property test for invalid JSON handling
    - **Property 3: Invalid JSON Graceful Handling**
    - **Validates: Requirements 3.3**

  - [ ]* 2.5 Write property test for non-numeric value rejection
    - **Property 4: Non-Numeric Value Rejection**
    - **Validates: Requirements 3.5**

  - [ ]* 2.6 Write property test for rotation value clamping
    - **Property 7: Rotation Value Clamping**
    - **Validates: Requirements 4.4**

- [x] 3. Implement rotation application logic
  - [x] 3.1 Add rotation application to RotationController
    - Add RotationMode enum (ABSOLUTE, RELATIVE)
    - Add exported cube_path, rotation_mode, smooth_rotation, rotation_speed
    - Implement `apply_rotation(rotation_data: Dictionary) -> void`
    - Implement `set_rotation_mode(mode: RotationMode) -> void`
    - Handle absolute mode: set rotation_degrees directly
    - Handle relative mode: add to current rotation_degrees
    - Implement smooth rotation interpolation in `_process(delta)`
    - _Requirements: 4.1, 4.2, 4.3, 4.5, 5.2_

  - [ ]* 3.2 Write property test for absolute rotation application
    - **Property 5: Absolute Rotation Application**
    - **Validates: Requirements 4.1, 4.2**

  - [ ]* 3.3 Write property test for relative rotation application
    - **Property 6: Relative Rotation Application**
    - **Validates: Requirements 4.2**

  - [ ]* 3.4 Write property test for state persistence without input
    - **Property 8: State Persistence Without Input**
    - **Validates: Requirements 4.5**

  - [ ]* 3.5 Write property test for runtime mode switching
    - **Property 10: Runtime Mode Switching**
    - **Validates: Requirements 5.2**

- [x] 4. Checkpoint - Ensure rotation logic tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 5. Implement MQTT client
  - [x] 5.1 Create MQTTClient autoload with connection management
    - Create `mqtt_client.gd` extending Node
    - Add signals: connected, disconnected, message_received, rotation_received
    - Add StreamPeerTCP socket management
    - Implement `connect_to_broker() -> Error`
    - Implement `disconnect_from_broker() -> void`
    - Implement MQTT 3.1.1 CONNECT packet construction
    - Handle CONNACK response
    - Load configuration from MQTTConfig resource or use defaults
    - _Requirements: 2.1, 2.5, 5.1_

  - [x] 5.2 Implement MQTT subscription and message handling
    - Implement `subscribe(topic: String) -> Error`
    - Implement MQTT SUBSCRIBE packet construction
    - Handle SUBACK response
    - Implement `_process_incoming_data()` for PUBLISH packets
    - Parse incoming rotation messages and emit rotation_received signal
    - _Requirements: 2.2, 3.1_

  - [x] 5.3 Implement connection retry and keepalive
    - Add reconnect timer with configurable delay
    - Implement PINGREQ/PINGRESP for keepalive
    - Handle connection failures with automatic retry
    - Implement graceful disconnect on tree exit
    - _Requirements: 2.3, 2.4_

  - [ ]* 5.4 Write property test for configuration values applied
    - **Property 9: Configuration Values Applied**
    - **Validates: Requirements 2.5**

  - [ ]* 5.5 Write property test for invalid configuration defaults
    - **Property 11: Invalid Configuration Defaults**
    - **Validates: Requirements 5.4**

- [x] 6. Wire components together
  - [x] 6.1 Register MQTTClient as autoload and connect signals
    - Add MQTTClient to project autoloads in project.godot
    - Add RotationController node to main scene
    - Connect MQTTClient.rotation_received to RotationController.apply_rotation
    - Configure RotationController cube_path to point to MeshInstance3D
    - _Requirements: 4.1_

  - [x] 6.2 Add cube configuration options
    - Add exported variables for cube size, color, material properties
    - Apply configuration in _ready()
    - Validate configuration and use defaults for invalid values
    - _Requirements: 5.3, 5.4_

- [x] 7. Final checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- GDScript is used throughout as it's the native Godot scripting language
- MQTT implementation uses raw StreamPeerTCP to avoid external dependencies
- GUT (Godot Unit Test) framework recommended for property-based testing
- Each property test should run minimum 100 iterations
