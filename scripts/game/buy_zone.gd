class_name BuyZone extends Area3D

## Поместите на карту в elimination при buy_requires_buy_zone.
## collision_mask должен видеть слой персонажей (2).
enum AllowedTeam {
	ANY = 0,
	ALPHA = 1,
	BRAVO = 2,
}

@export var allowed_team: int = AllowedTeam.ANY


func _ready() -> void:
	add_to_group("buy_zones")
	monitoring = true
	monitorable = true


func allows_team(team_id: int) -> bool:
	return allowed_team == AllowedTeam.ANY or allowed_team == team_id


func overlaps_player_body(player: Node3D) -> bool:
	return overlaps_body(player)
