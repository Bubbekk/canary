-- Rates por etapas (rateUseStages = true en config.lua).
-- Experiencia: fácil hasta nivel 400, después la subida se vuelve lenta (objetivo: ~1 año para niveles muy altos).
-- Skills y magic level: rápidos hasta 90 y luego cada vez más lentos.
-- La bonificación VIP (+10% exp y skills) se suma encima.

experienceStages = {
	{
		minlevel = 1,
		maxlevel = 50,
		multiplier = 50,
	},
	{
		minlevel = 51,
		maxlevel = 100,
		multiplier = 35,
	},
	{
		minlevel = 101,
		maxlevel = 200,
		multiplier = 25,
	},
	{
		minlevel = 201,
		maxlevel = 300,
		multiplier = 15,
	},
	{
		minlevel = 301,
		maxlevel = 400,
		multiplier = 10,
	},
	{
		minlevel = 401,
		maxlevel = 500,
		multiplier = 5,
	},
	{
		minlevel = 501,
		maxlevel = 600,
		multiplier = 3,
	},
	{
		minlevel = 601,
		maxlevel = 800,
		multiplier = 2,
	},
	{
		minlevel = 801,
		multiplier = 1,
	},
}

skillsStages = {
	{
		minlevel = 0,
		maxlevel = 60,
		multiplier = 30,
	},
	{
		minlevel = 61,
		maxlevel = 80,
		multiplier = 20,
	},
	{
		minlevel = 81,
		maxlevel = 90,
		multiplier = 15,
	},
	{
		minlevel = 91,
		maxlevel = 100,
		multiplier = 6,
	},
	{
		minlevel = 101,
		maxlevel = 110,
		multiplier = 4,
	},
	{
		minlevel = 111,
		maxlevel = 120,
		multiplier = 2,
	},
	{
		minlevel = 121,
		multiplier = 1,
	},
}

magicLevelStages = {
	{
		minlevel = 0,
		maxlevel = 40,
		multiplier = 20,
	},
	{
		minlevel = 41,
		maxlevel = 70,
		multiplier = 12,
	},
	{
		minlevel = 71,
		maxlevel = 90,
		multiplier = 8,
	},
	{
		minlevel = 91,
		maxlevel = 100,
		multiplier = 4,
	},
	{
		minlevel = 101,
		maxlevel = 110,
		multiplier = 2,
	},
	{
		minlevel = 111,
		multiplier = 1,
	},
}
