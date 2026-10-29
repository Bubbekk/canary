-- Todos los hechizos son gratuitos para todos los jugadores (premium o no).
-- Los scripts de hechizos y runas marcan algunos como premium con spell:isPremium(true);
-- aquí se ignora esa marca al registrarlos, sin tocar cada archivo ni el C++.
-- Para volver al comportamiento original, borra este archivo y su línea en load.lua.
local nativeIsPremium = Spell.isPremium

function Spell.isPremium(self, premium)
	if premium ~= nil then
		return nativeIsPremium(self, false)
	end
	return nativeIsPremium(self)
end
