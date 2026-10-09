-- Mini framework de tests : describe / it / assertions, avec récapitulatif des échecs.
local Test = {
	passed = 0,
	failures = {},
}

local scope: { string } = {}

-- Cette méthode permet de regrouper des tests sous un nom commun lorsqu'un spec est structuré par module.
function Test.describe(name: string, fn: () -> ())
	table.insert(scope, name)
	fn()
	table.remove(scope)
end

-- Cette méthode permet d'exécuter un cas de test isolé lorsque fn ne lève pas d'erreur il est compté réussi.
function Test.it(name: string, fn: () -> ())
	local fullName = table.concat(scope, " > ") .. " > " .. name
	local ok, err = pcall(fn)
	if ok then
		Test.passed += 1
	else
		table.insert(Test.failures, { name = fullName, err = tostring(err) })
	end
end

-- Cette méthode permet de vérifier une condition lorsque le message décrit l'attendu.
function Test.expect(cond: any, message: string?)
	if not cond then
		error(message or "assertion échouée", 2)
	end
end

-- Cette méthode permet de comparer deux valeurs à une tolérance près lorsque l'on manipule des flottants.
function Test.expectNear(actual: number, expected: number, eps: number?, message: string?)
	local tolerance = eps or 1e-6
	if math.abs(actual - expected) > tolerance then
		error(
			string.format(
				"%sattendu %.6f ± %g, obtenu %.6f",
				message and (message .. " : ") or "",
				expected,
				tolerance,
				actual
			),
			2
		)
	end
end

-- Cette méthode permet de comparer deux valeurs par égalité stricte.
function Test.expectEqual(actual: any, expected: any, message: string?)
	if actual ~= expected then
		error(
			string.format(
				"%sattendu %s, obtenu %s",
				message and (message .. " : ") or "",
				tostring(expected),
				tostring(actual)
			),
			2
		)
	end
end

return Test
