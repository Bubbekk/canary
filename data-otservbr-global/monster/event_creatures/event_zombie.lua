-- Zombie del Zombie Event (data/scripts/systems/rot_zombie_event.lua).
-- No se puede atacar ni da experiencia ni loot: un solo toque elimina al jugador (lo decide el script).
local mType = Game.createMonsterType("Event Zombie")
local monster = {}

monster.description = "an event zombie"
monster.experience = 0
monster.outfit = {
	lookType = 311,
	lookHead = 0,
	lookBody = 0,
	lookLegs = 0,
	lookFeet = 0,
	lookAddons = 0,
	lookMount = 0,
}

monster.health = 100000
monster.maxHealth = 100000
monster.race = "undead"
monster.corpse = 0
monster.speed = 175
monster.manaCost = 0

monster.changeTarget = {
	interval = 3000,
	chance = 20,
}

monster.strategiesTarget = {
	nearest = 100,
}

monster.flags = {
	summonable = false,
	attackable = false,
	hostile = true,
	convinceable = false,
	pushable = false,
	rewardBoss = false,
	illusionable = false,
	canPushItems = true,
	canPushCreatures = false,
	staticAttackChance = 95,
	targetDistance = 1,
	runHealth = 0,
	healthHidden = true,
	isBlockable = false,
	canWalkOnEnergy = true,
	canWalkOnFire = true,
	canWalkOnPoison = true,
}

monster.light = {
	level = 0,
	color = 0,
}

monster.voices = {
	interval = 5000,
	chance = 10,
	{ text = "Brrrains...", yell = false },
	{ text = "Mst.... klll....", yell = false },
	{ text = "Grrrrl...", yell = false },
}

monster.loot = {}

monster.attacks = {
	{ name = "melee", interval = 1000, chance = 100, minDamage = -1, maxDamage = -1 },
}

monster.defenses = {
	defense = 100,
	armor = 100,
}

monster.elements = {}

monster.immunities = {
	{ type = "paralyze", condition = true },
	{ type = "outfit", condition = true },
	{ type = "invisible", condition = true },
	{ type = "bleed", condition = true },
}

mType:register(monster)
