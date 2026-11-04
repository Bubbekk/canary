-- Precios de la tienda de RoT.
--
-- La tabla se aplica en gamestore.lua después de cargar el catálogo. Los
-- multiplicadores se aplican al precio base de Tibia y los overrides por id
-- permiten fijar precios exactos (VIP).
--
-- Referencia de equilibrio: 1 Tibia Coin ≈ 1 hora de juego VIP (0.5/h gratis),
-- de modo que un consumible de 100 unidades cueste unas pocas horas, un mount
-- de gama media ronde las 300 horas y el VIP mensual no sea inalcanzable.
return {
	multipliers = {
		-- Consumibles: -40%
		["Potions"] = 0.6,
		["Runes"] = 0.6,
		["Casks"] = 0.6,
		["Kegs"] = 0.6,

		-- Bendiciones: -20%
		["Blessings"] = 0.8,

		-- Entrenamiento: -50%
		["Exercise Weapons"] = 0.5,

		-- Cosmética: -60% (sigue siendo aspiracional)
		["Mounts"] = 0.4,
		["Outfits"] = 0.4,

		-- Casa: -60%
		["Decorations"] = 0.4,
		["Furniture"] = 0.4,
		["Beds"] = 0.4,
		["Upgrades"] = 0.4,
		["Hirelings"] = 0.4,
		["Hireling Dresses"] = 0.4,

		-- Servicios: -50%
		["Extra Services"] = 0.5,
		["Useful Things"] = 0.5,

		-- Los exclusivos de torneo mantienen su precio de prestigio.
		["Exclusive Offers"] = 1.0,
	},

	overrides = {
		byId = {
			-- VIP: 1 día gratis, 1 semana, 1 mes y permanente.
			[3001] = 0,
			[3007] = 40,
			[3030] = 150,
			[68534] = 2500,

			-- Primer XP Boost (el resto se controla con expBoost).
			[65010] = 20,
		},
	},

	-- Precio de los 5 XP Boosts comprables entre guardados globales.
	expBoost = { 20, 30, 60, 120, 240 },
}
