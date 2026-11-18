-- Double de CheatLog pour les specs : `admit` suit `admitted` (true par défaut) et retient le dernier remote contrôlé.
local CheatLogStub = { admitted = true, lastRemote = nil :: string? }

-- Cette méthode permet de simuler la garde des remotes lorsqu'un module appelle CheatLog.admit.
function CheatLogStub.admit(_player: any, remoteName: string, ...: any): boolean
	CheatLogStub.lastRemote = remoteName
	return CheatLogStub.admitted
end

return CheatLogStub
