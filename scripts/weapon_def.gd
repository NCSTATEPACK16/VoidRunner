class_name WeaponDef
extends Resource
## One weapon's tuning (PLAN.md F1). Values ship in resources/weapons/*.tres —
## the Godot equivalent of the web build's WEAPONS config table.

@export var display_name := "NEUTRON"
@export var heat := 8.0
@export var cooldown := 0.17
@export var speed := 170.0
@export var damage := 1
@export var count := 2          # projectiles per trigger pull
@export var spread := 0.0       # radians between spread shots
@export var sprite_scale := 1.0
@export var color := Color("55ffee")
@export var freq := 980.0       # laser sfx start pitch
@export var fuse := 0.0         # seconds; 0 = no fuse (MISSILE uses 2.0)
@export var splash := 0.0       # blast radius; 0 = no splash
@export var splash_damage := 0
