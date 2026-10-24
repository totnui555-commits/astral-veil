extends RefCounted
class_name CombatSkills

## Thirty class abilities share the world's collision, damage and status rules.
## Costs and cooldowns belong to World; this module only resolves an approved cast.
static func cast(world, actor, ultimate: bool = false) -> void:
	if not is_instance_valid(actor) or float(actor.hp) <= 0.0:
		return
	var skill: String = str(actor.definition.get("skill", "cleave"))
	var origin: Vector2 = actor.position
	var direction: Vector2 = actor.facing
	if direction.length_squared() < 0.01:
		direction = Vector2.RIGHT
	direction = direction.normalized()
	var target = world.nearest_enemy(origin)
	if _alive(target) and origin.distance_to(target.position) < 580.0:
		direction = origin.direction_to(target.position)
	var target_position: Vector2 = origin + direction * 150.0
	if _alive(target):
		target_position = origin + (target.position - origin).limit_length(300.0)
	var attack: float = maxf(1.0, float(actor.attack_power))
	var magic: float = maxf(1.0, float(actor.magic_power))
	var power: float = maxf(attack, magic)
	var blue: Color = Color("78d9ff")
	var gold: Color = Color("ffe39c")
	var violet: Color = Color("c092ff")
	var green: Color = Color("8ff2aa")
	var red: Color = Color("ff8366")
	match skill:
		"cleave":
			# Vanguard: directional reach; the ultimate becomes a full cyclone.
			_cone(world, actor, origin, direction, 175.0 if ultimate else 118.0,
				-1.0 if ultimate else 0.10, attack * (2.7 if ultimate else 1.65), 46.0)
			world.effect(origin, "crescent", 175.0 if ultimate else 100.0, gold, 0.5)
			if ultimate:
				_status_area(world, origin, 175.0, "stun", 1.5)
		"shield":
			# Bulwark: survive a telegraph, then stagger enemies at close range.
			for ally in _allies(world, actor, 900.0 if ultimate else 0.0):
				world.apply_status(ally, "shield", 10.0 if ultimate else 6.0)
				world.effect(ally.position, "aegis", 42.0, blue, 0.8)
				if ultimate:
					world.heal_actor(ally, float(ally.max_hp) * 0.18)
			world.area_damage(origin, 180.0 if ultimate else 96.0,
				attack * (1.4 if ultimate else 0.7), actor, "stun", 2.0 if ultimate else 0.7)
		"arc":
			# Stormblade: each link chooses a new nearby enemy, never one twice.
			_chain_lightning(world, actor, target, 8 if ultimate else 3,
				power * (1.65 if ultimate else 1.15), ultimate)
		"nova":
			# Spellweaver: a large remote blast, with a lingering astral core.
			world.area_damage(target_position, 215.0 if ultimate else 110.0,
				magic * (3.0 if ultimate else 1.9), actor, "weakness", 5.0 if ultimate else 2.0)
			world.effect(target_position, "nova", 215.0 if ultimate else 110.0, violet, 0.75)
			if ultimate:
				world.add_zone(target_position, 140.0, 5.0, magic * 0.40, actor, "glyph")
		"volley":
			# Ranger: fan coverage; every ultimate arrow pierces its first target.
			_fan(world, actor, origin, direction, 11 if ultimate else 5,
				0.105 if ultimate else 0.15, attack * (1.05 if ultimate else 0.75), green, 540.0, ultimate)
		"summon":
			# Summoner: independent creatures pursue and fight for a limited time.
			var count: int = 4 if ultimate else 2
			for index in range(count):
				var offset: Vector2 = Vector2.from_angle(TAU * float(index) / float(count)) * 44.0
				world.add_summon(origin + offset, actor, "spirit", 21.0 if ultimate else 12.0)
			world.effect(origin, "ring", 85.0, violet, 0.9)
		"heal":
			# Sanctifier: triage the most wounded ally, or rescue the whole party.
			if ultimate:
				for ally in _allies(world, actor, 1000.0):
					world.heal_actor(ally, float(ally.max_hp) * 0.55 + magic)
					world.apply_status(ally, "shield", 5.0)
					world.apply_status(ally, "regen", 8.0)
					world.effect(ally.position, "heal", 60.0, green, 1.0)
			else:
				var patient = _most_wounded(world, actor)
				world.heal_actor(patient, magic * 2.8 + float(patient.max_hp) * 0.15)
				world.apply_status(patient, "regen", 5.0)
				world.effect(patient.position, "heal", 54.0, green, 0.8)
		"curse":
			# Hexbinder: enfeeble a cluster; the ultimate layers poison and slow.
			var curse_radius: float = 180.0 if ultimate else 95.0
			world.area_damage(target_position, curse_radius, magic * (1.8 if ultimate else 1.05),
				actor, "weakness", 10.0 if ultimate else 6.0)
			_status_area(world, target_position, curse_radius, "poison", 8.0 if ultimate else 4.0)
			if ultimate:
				_status_area(world, target_position, curse_radius, "slow", 7.0)
			world.effect(target_position, "ring", curse_radius, violet, 0.8)
		"time":
			# Chronomancer: friendly time speeds up while hostile time slows down.
			for ally in _allies(world, actor, 900.0 if ultimate else 200.0):
				world.apply_status(ally, "haste", 10.0 if ultimate else 5.0)
			_status_area(world, origin, 290.0 if ultimate else 165.0, "slow", 8.0 if ultimate else 5.0)
			if ultimate:
				_status_area(world, origin, 290.0, "freeze", 3.0)
			world.effect(origin, "ring", 290.0 if ultimate else 165.0, blue, 1.0)
		"poison":
			# Venomist: toxic ground rewards keeping enemies inside its radius.
			var poison_radius: float = 145.0 if ultimate else 95.0
			world.add_zone(target_position, poison_radius, 10.0 if ultimate else 6.0,
				magic * (0.65 if ultimate else 0.38), actor, "poison")
			_status_area(world, target_position, poison_radius, "poison", 10.0 if ultimate else 6.0)
			if ultimate:
				_status_area(world, target_position, poison_radius, "root", 3.0)
			world.effect(target_position, "burst", poison_radius, green, 0.7)
		"turret":
			# Artificer: stationary sentries cover the battlefield from fixed points.
			var sentries: int = 3 if ultimate else 1
			for index in range(sentries):
				var offset: Vector2 = Vector2.from_angle(TAU * float(index) / float(sentries)) * 48.0
				world.add_summon(origin + offset, actor, "turret", 22.0 if ultimate else 14.0)
			world.effect(origin, "ring", 70.0, gold, 0.7)
		"blink":
			# Riftwalker: world collision validates every step of the displacement.
			world.effect(origin, "burst", 42.0, violet, 0.35)
			world.move_actor(actor, direction * (235.0 if ultimate else 155.0))
			world.area_damage(actor.position, 125.0 if ultimate else 78.0,
				power * (2.8 if ultimate else 1.45), actor, "slow", 4.0)
			world.apply_status(actor, "invisible", 4.0 if ultimate else 1.8)
			world.effect(actor.position, "burst", 95.0, violet, 0.55)
		"drain":
			# Bloodsage: siphon has a strict range and heals only after a real hit.
			var drained: int = 0
			var drain_damage: float = magic * (1.8 if ultimate else 1.5)
			for enemy in _targets(world, origin, 290.0 if ultimate else 230.0):
				if drained >= (5 if ultimate else 1):
					break
				var stolen: float = world.damage_enemy(enemy, drain_damage, actor)
				world.heal_actor(actor, stolen * (0.7 if ultimate else 0.55))
				world.effect(enemy.position, "burst", 34.0, red, 0.6)
				drained += 1
			world.effect(origin, "heal", 48.0, red, 0.7)
		"enchant":
			# Runeknight: empower attacks and release an enchanted blade wave.
			for ally in _allies(world, actor, 900.0 if ultimate else 0.0):
				world.apply_status(ally, "empower", 12.0 if ultimate else 8.0)
				if ultimate:
					world.apply_status(ally, "haste", 7.0)
				world.effect(ally.position, "ring", 45.0, gold, 0.8)
			world.projectile(origin, direction, power * (2.5 if ultimate else 1.35), actor, gold, 490.0, true)
		"chain":
			# Chainwarden: drag a cluster toward the caster and bind it in place.
			var anchor: Vector2 = origin + direction * 60.0
			for enemy in _targets(world, target_position, 150.0 if ultimate else 80.0):
				var pull: Vector2 = (anchor - enemy.position).limit_length(115.0 if ultimate else 65.0)
				world.damage_enemy(enemy, attack * (1.9 if ultimate else 1.05), actor, pull)
				if _alive(enemy):
					world.apply_status(enemy, "root", 5.0 if ultimate else 3.0)
			world.effect(target_position, "ring", 150.0 if ultimate else 80.0, gold, 0.65)
		"fire":
			# Pyromancer: a cone of flame leaves damaging ground behind it.
			_cone(world, actor, origin, direction, 280.0 if ultimate else 180.0,
				0.35 if ultimate else 0.65, magic * (2.0 if ultimate else 1.15), 0.0)
			var flames: int = 4 if ultimate else 1
			for index in range(flames):
				var angle: float = (float(index) - float(flames - 1) * 0.5) * 0.32
				world.add_zone(origin + direction.rotated(angle) * (155.0 if ultimate else 125.0),
					86.0 if ultimate else 65.0, 8.0 if ultimate else 5.0,
					magic * (0.52 if ultimate else 0.35), actor, "fire")
			world.effect(origin + direction * 110.0, "burst", 120.0, red, 0.6)
		"freeze":
			# Cryomancer: remote hard control; the ultimate also creates shelter.
			world.area_damage(target_position, 200.0 if ultimate else 102.0,
				magic * (2.15 if ultimate else 1.15), actor, "freeze", 4.0 if ultimate else 2.5)
			world.effect(target_position, "burst", 200.0 if ultimate else 102.0, blue, 0.9)
			if ultimate:
				world.add_zone(target_position, 150.0, 6.0, magic * 0.32, actor, "frost")
				world.apply_status(actor, "shield", 6.0)
		"stealth":
			# Shadow: prepare an empowered ambush and escape hostile attention.
			if ultimate:
				_cone(world, actor, origin, direction, 175.0, -0.25, attack * 3.2, 0.0)
				_status_area(world, origin, 175.0, "weakness", 5.0)
			world.apply_status(actor, "invisible", 8.0 if ultimate else 5.0)
			world.apply_status(actor, "empower", 7.0 if ultimate else 4.0)
			world.apply_status(actor, "haste", 5.0 if ultimate else 3.0)
			world.effect(origin, "burst", 65.0, violet, 0.7)
		"dragon":
			# Dragoon: a lunging impact; dragonfall adds a piercing breath fan.
			world.move_actor(actor, direction * (170.0 if ultimate else 105.0))
			world.area_damage(actor.position, 145.0 if ultimate else 93.0,
				attack * (2.5 if ultimate else 1.55), actor, "stun", 2.0 if ultimate else 0.8)
			world.effect(actor.position, "burst", 145.0 if ultimate else 93.0, red, 0.7)
			if ultimate:
				_fan(world, actor, actor.position, direction, 7, 0.16, power * 1.2, red, 430.0, true)
		"foresight":
			# Oracle: a brief defensive window and an exposed enemy weak point.
			for ally in _allies(world, actor, 900.0 if ultimate else 0.0):
				world.apply_status(ally, "shield", 5.0 if ultimate else 2.5)
				world.apply_status(ally, "empower", 8.0 if ultimate else 5.0)
				world.effect(ally.position, "ring", 50.0, blue, 0.85)
			if _alive(target) and origin.distance_to(target.position) <= 380.0:
				world.apply_status(target, "weakness", 10.0 if ultimate else 6.0)
				world.effect(target.position, "ring", 38.0, gold, 0.8)
			if ultimate:
				_status_area(world, origin, 280.0, "stun", 2.0)
		"anthem":
			# Songweaver: sustained party tempo and recovery, with no direct hit.
			for ally in _allies(world, actor, 1000.0 if ultimate else 270.0):
				world.apply_status(ally, "haste", 12.0 if ultimate else 6.0)
				world.apply_status(ally, "regen", 12.0 if ultimate else 6.0)
				if ultimate:
					world.apply_status(ally, "empower", 10.0)
				world.effect(ally.position, "heal", 55.0, gold, 1.0)
			world.effect(origin, "ring", 240.0, gold, 1.1)
		"spirits":
			# Medium: a healing rite calls ancestral defenders to the party.
			var patient = _most_wounded(world, actor)
			world.heal_actor(patient, magic * (2.5 if ultimate else 1.55))
			world.add_summon(patient.position + Vector2(35.0, 0.0), actor, "spirit", 16.0 if ultimate else 8.0)
			world.effect(patient.position, "heal", 65.0, blue, 0.9)
			if ultimate:
				for ally in _allies(world, actor, 1000.0):
					world.apply_status(ally, "regen", 10.0)
					world.add_summon(ally.position + Vector2(-35.0, 0.0), actor, "spirit", 12.0)
		"pierce":
			# Deadeye: a narrow, fast shot passes through the entire enemy line.
			if ultimate:
				var tangent: Vector2 = direction.orthogonal()
				for lane in range(-1, 2):
					world.projectile(origin + tangent * float(lane) * 23.0, direction,
						attack * 2.7, actor, gold, 780.0, true)
			else:
				world.projectile(origin, direction, attack * 2.15, actor, gold, 740.0, true)
			world.effect(origin, "crescent", 42.0, gold, 0.3)
		"drone":
			# Machinist: mobile drones accompany the party; overload adds cover.
			world.add_summon(origin + Vector2(32.0, -30.0), actor, "drone", 24.0 if ultimate else 15.0)
			if ultimate:
				world.add_summon(origin + Vector2(-32.0, -30.0), actor, "drone", 24.0)
				world.apply_status(actor, "shield", 8.0)
				_fan(world, actor, origin, direction, 5, 0.2, attack, blue, 570.0, false)
			world.effect(origin, "ring", 55.0, blue, 0.65)
		"roots":
			# Verdantkeeper: immobilizing roots persist as a bramble damage field.
			var root_radius: float = 205.0 if ultimate else 108.0
			world.area_damage(target_position, root_radius, magic * (1.8 if ultimate else 0.85),
				actor, "root", 7.0 if ultimate else 4.0)
			world.add_zone(target_position, root_radius, 9.0 if ultimate else 5.0,
				magic * 0.32, actor, "roots")
			if ultimate:
				for ally in _allies(world, actor, 1000.0):
					world.apply_status(ally, "regen", 8.0)
			world.effect(target_position, "ring", root_radius, green, 0.9)
		"execute":
			# Reaper: missing health increases damage; bosses remain damageable.
			if _alive(target) and origin.distance_to(target.position) <= (290.0 if ultimate else 170.0):
				var missing: float = 1.0 - clampf(float(target.hp) / maxf(1.0, float(target.max_hp)), 0.0, 1.0)
				var execution: float = attack * ((2.6 + missing * 5.2) if ultimate else (1.35 + missing * 2.8))
				var mark_position: Vector2 = target.position
				world.damage_enemy(target, execution, actor)
				world.effect(mark_position, "slash", 82.0 if ultimate else 55.0, red, 0.65)
				if ultimate:
					world.area_damage(mark_position, 100.0, attack * (0.8 + missing), actor, "weakness", 5.0)
		"flurry":
			# Duelist: three close strikes, or a sweeping six-strike dance.
			world.move_actor(actor, direction * 38.0)
			var strikes: int = 6 if ultimate else 3
			for index in range(strikes):
				var strike_direction: Vector2 = direction.rotated(TAU * float(index) / float(strikes)) if ultimate else direction.rotated((float(index) - 1.0) * 0.25)
				_cone(world, actor, actor.position, strike_direction, 125.0 if ultimate else 93.0,
					-0.25 if ultimate else 0.2, attack * (0.62 if ultimate else 0.55), 4.0)
				world.effect(actor.position + strike_direction * 42.0, "slash", 50.0, gold, 0.35 + float(index) * 0.06)
			world.apply_status(actor, "haste", 6.0 if ultimate else 2.5)
		"gravity":
			# Graviturge: pull enemies toward a chosen singularity, then slow them.
			var gravity_radius: float = 265.0 if ultimate else 155.0
			for enemy in _targets(world, target_position, gravity_radius):
				var pull: Vector2 = (target_position - enemy.position).limit_length(160.0 if ultimate else 85.0)
				world.damage_enemy(enemy, magic * (2.0 if ultimate else 1.05), actor, pull)
				if _alive(enemy):
					world.apply_status(enemy, "slow", 7.0 if ultimate else 4.0)
					if ultimate:
						world.apply_status(enemy, "stun", 2.0)
			world.add_zone(target_position, 135.0 if ultimate else 75.0, 6.0 if ultimate else 3.0,
				magic * 0.35, actor, "gravity")
			world.effect(target_position, "ring", gravity_radius, violet, 1.0)
		"glyph":
			# Sigilist: protective inscription; the ultimate draws three rune traps.
			var glyph_count: int = 3 if ultimate else 1
			for index in range(glyph_count):
				var rune: Vector2 = target_position
				if ultimate:
					rune += Vector2.from_angle(TAU * float(index) / 3.0) * 88.0
				world.add_zone(rune, 94.0, 10.0 if ultimate else 7.0,
					magic * (0.55 if ultimate else 0.42), actor, "glyph")
				world.area_damage(rune, 94.0, magic * 0.75, actor, "root", 2.5 if ultimate else 1.5)
				world.effect(rune, "ring", 94.0, violet, 0.85)
			world.apply_status(actor, "shield", 7.0 if ultimate else 3.0)
		"frenzy":
			# Berserker: sacrifice a little health for a sustained offensive window.
			if ultimate:
				world.heal_actor(actor, float(actor.max_hp) * 0.30)
				world.apply_status(actor, "shield", 6.0)
			else:
				actor.hp = maxf(1.0, float(actor.hp) - float(actor.max_hp) * 0.08)
			world.apply_status(actor, "frenzy", 13.0 if ultimate else 8.0)
			world.apply_status(actor, "haste", 10.0 if ultimate else 5.0)
			world.area_damage(origin, 155.0 if ultimate else 85.0,
				attack * (1.8 if ultimate else 0.65), actor, "weakness", 5.0)
			world.effect(origin, "burst", 120.0, red, 0.8)
		_:
			world.area_damage(origin + direction * 55.0, 95.0, power * 1.5, actor)
			world.effect(origin, "crescent", 95.0, gold, 0.5)


static func _alive(entity) -> bool:
	return is_instance_valid(entity) and float(entity.hp) > 0.0


static func _targets(world, center: Vector2, radius: float) -> Array:
	var result: Array = []
	for enemy in world.enemies.duplicate():
		if _alive(enemy) and center.distance_squared_to(enemy.position) <= radius * radius and world._has_line(center, enemy.position):
			result.append(enemy)
	# Stable nearest-first selection makes siphons and chain origins predictable.
	result.sort_custom(func(a, b): return center.distance_squared_to(a.position) < center.distance_squared_to(b.position))
	return result


static func _allies(world, source, radius: float) -> Array:
	var result: Array = []
	for ally in world.actors:
		if _alive(ally) and (ally == source or source.position.distance_to(ally.position) <= radius):
			result.append(ally)
	return result


static func _most_wounded(world, source):
	var patient = source
	var lowest: float = float(source.hp) / maxf(1.0, float(source.max_hp))
	for ally in _allies(world, source, 650.0):
		var fraction: float = float(ally.hp) / maxf(1.0, float(ally.max_hp))
		if fraction < lowest:
			lowest = fraction
			patient = ally
	return patient


static func _status_area(world, center: Vector2, radius: float, status: String, duration: float) -> void:
	for enemy in _targets(world, center, radius):
		world.apply_status(enemy, status, duration)


static func _cone(world, source, center: Vector2, direction: Vector2, radius: float,
		minimum_dot: float, damage: float, push: float) -> void:
	for enemy in _targets(world, center, radius):
		var toward: Vector2 = center.direction_to(enemy.position)
		if toward == Vector2.ZERO or toward.dot(direction) >= minimum_dot:
			world.damage_enemy(enemy, damage, source, toward * push)


static func _fan(world, source, center: Vector2, direction: Vector2, count: int,
		spread: float, damage: float, color: Color, speed: float, piercing: bool) -> void:
	for index in range(count):
		var angle: float = (float(index) - float(count - 1) * 0.5) * spread
		world.projectile(center, direction.rotated(angle), damage, source, color, speed, piercing)


static func _chain_lightning(world, source, first, links: int, damage: float, ultimate: bool) -> void:
	if not _alive(first) or source.position.distance_to(first.position) > 350.0:
		return
	var hit: Array = []
	var current = first
	for index in range(links):
		if not _alive(current):
			break
		var current_position: Vector2 = current.position
		hit.append(current)
		world.damage_enemy(current, damage * pow(0.90, float(index)), source)
		world.effect(current_position, "skybreak", 44.0, Color("9be5ff"), 0.55)
		if _alive(current):
			world.apply_status(current, "stun", 1.5 if ultimate else 0.35)
		current = null
		for candidate in _targets(world, current_position, 250.0 if ultimate else 180.0):
			if not hit.has(candidate):
				current = candidate
				break
