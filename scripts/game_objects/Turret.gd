class_name Turret
extends Node3D

var cooldown = 0
var active = false
var target = Vector3.BACK*3 + Vector3.UP

func _ready() -> void:
    add_to_group("Turrets")

func shoot_laser(starting_position: Vector3, target_position: Vector3):
    var laser_instance = DefaultLaser.new()
    laser_instance.global_position = starting_position
    laser_instance.direction = target_position - starting_position
    laser_instance.emitter = get_parent()
    laser_instance.color = get_parent().laser_color
    get_tree().get_root().add_child(laser_instance)

func _process(delta: float) -> void:
    cooldown -= delta

    if active and cooldown <= 0:
        shoot_laser(global_position, target)
        cooldown = .2
