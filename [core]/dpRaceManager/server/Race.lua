--- Класс гонки
-- @module dpRaceManager.Race
-- @author Wherry

local DEFAULT_RACE_DURATION = 300

Race = newclass("Race")

-- Конструктор
-- table settings - таблица настроек гонки
function Race:init(settings)
	---- Состояние гонки. 
	-- Нельзя изменить напрямую, только через race:setState(state)
	-- Возможные состояния: 
	-- no_map 	- карта ещё не загружена. Нельзя добавлять или удалять игроков.
	-- waiting 	- ожидание старта. Можно добавлять и удалять игроков.
	-- running	- непосредственно гонка. Нельзя добавлять игроков, но можно удалять игроков.
	-- finished - гонка завершилась. Нельзя добавлять игроков, но можно удалять игроков.
	self._state = "no_map"

	---- Настройки гонки
	-- number duration 		- продолжительность гонки в секундах
	-- bool noSpawnpoints 	- начать гонку в точках, где находятся игроки, в данный момент.
	--						Если у трассы нет спавнпойнтов, гонка начнется в точках, где
	--						находятся игроки, в данный момент.
	-- bool separateDimension - использовать отдельный dimension
	--						По умолчанию игроки переносятся в отдельный dimension, чтобы не
	--						происходило случаных помех или падений фпс из-за скоплений игроков.
	-- bool createVehicles	- создать автомобиль для участников гонки. TODO: Пока не нужно  
	-- bool fadeCameraOnJoin - затемнять камеру игрока при добавлении его в гонку
	self.settings = {
		duration = 10,
		noSpawnpoints = false,
		separateDimension = true,
		createVehicles = false,
		fadeCameraOnJoin = true
	}
	-- Установить не указанные настройки по умолчанию
	self.settings = exports.dpUtils:extendTable(settings, self.settings)
	-- Участники гонки
	self.players = {}
	-- Dimension гонки
	self.dimension = 0

	self.gameplay = RaceGameplay(self)	
end

-- Гонка была добавлена в RaceManager
function Race:onAdded()
	if self.settings.separateDimension then
		-- Выбор dimension'а в зависимости от id гонки
		self.dimension = 70000 + self.id
	end
end

--- Загрузка карты в гонку
-- @tparam table map гонка
function Race:loadMap(map)
	if type(map) ~= "table" then
		return false
	end
	-- Не заданы чекпойнты
	if type(map.checkpoints) ~= "table" or #map.checkpoints == 0 then
		return false
	end
	-- Значения по умолчанию
	self.map = exports.dpUtils:extendTable(map, {
		-- Длительность гонок из настроек
		duration = self.settings.duration,
		--weather = 0,
		--time = {12, 0}
	})
	self:setState("waiting")
	return true
end

-- Вызывает клиентский метод, определенный в client->Race, для всех игроков гонки
function Race:callMethod(methodName, ...)
	for i, player in ipairs(self.players) do
		self:callPlayerMethod(player, methodName, ...)
	end
	return true
end

-- Вызывает клиентский метод, определенный в client->Race, для указанного игрока
function Race:callPlayerMethod(player, methodName, ...)
	return triggerClientEvent(player, "dpRaceManager.rpc", resourceRoot, methodName, ...)
end

-- Смена состояния гонки
function Race:setState(state)
	if type(state) ~= "string" then
		return true
	end
	if self._state == state then
		return false
	end
	self._state = state
	-- Передать всем игрокам новое состояние гонки
	self:callMethod("updateState", state)
	return true
end

-- Возвращает текущее состояние гонки
function Race:getState()
	return self._state
end

--- Добавление игрока в гонку
function Race:addPlayer(player)
	if not isElement(player) or player.type ~= "player" then
		return false
	end
	-- Игрок уже находится в другой гонке
	if player:getData("race_id") then
		outputDebugString("Player '" .. tostring(player.name) .. "' is already in other race")
		return false
	end
	-- Игрок не находится в автомобиле, когда гонка требует машину игрока
	if not self.settings.createVehicles and not isElement(player.vehicle) then
		outputDebugString("Player '" .. tostring(player.name) .. "' must be in a vehicle to join this race")
		return false
	end
	-- Добавление игрока в список участников
	table.insert(self.players, player)
	player:setData("race_id", self.id)
	-- Обработка входа в гонку
	self.gameplay:onPlayerJoin(player)
	-- Вызов клиентских методов
	self:callPlayerMethod(player, "onJoin", self.settings)
	self:callMethod("onPlayerJoin", player)
	self:callPlayerMethod(player, "updateState", self:getState())
	return true
end

--- Проверка на нахождение игрока в гонке
function Race:isPlayerIn(player)
	if not isElement(player) or player.type ~= "player" then
		return false
	end	
	-- Поиск игрока в списке участников гонки 
	for i, p in ipairs(self.players) do
		if p == player then
			return true, i
		end
	end
	return false
end

--- Добавление нескольких игроков в гонку
function Race:addPlayers(playersTable)
	if type(playersTable) ~= "table" then
		return false
	end
	-- Добавление игроков из списка в гонку
	for i, player in ipairs(playersTable) do
		self:addPlayer(player)
	end
	return true
end

--- Удаление игрока из гонки
function Race:removePlayer(player)
	if not isElement(player) or player.type ~= "player" then
		return false
	end
	-- Если игрок не находится в гонке
	if not player:getData("race_id") then
		outputDebugString("Race:removePlayer - player is not in race")
		return false
	end
	-- Если игрок находится в другой гонке
	if player:getData("race_id") ~= self.id then
		outputDebugString("Race:removePlayer - player is in another race")
		return false
	end

	-- Удалить игрока
	for i, p in ipairs(self.players) do
		if p == player then
			-- Обработать выход игрока
			self.gameplay:onPlayerLeave(player)
			self:callPlayerMethod(player, "onLeave")
			self:callMethod("onPlayerLeave", player)
			-- Полностью удалить игрока из гонки
			player:removeData("race_id")
			table.remove(self.players, i)
			-- Если все игроки покинули гонку - удалить её
			if #self.players == 0 then
				self.raceManager:removeRace(self)
			end
			return true
		end
	end
	return false
end

--- Запуск гонки
function Race:start()
	self.gameplay:onRaceStart()

	local duration = self.settings.duration
	if type(self.settings.duration) ~= "number" then
		duration = DEFAULT_RACE_DURATION
	end

	local race = self
	self.durationTimer = setTimer(function()
		race:onTimeout()
	end, duration * 1000, 1)

	race:setState("running")
end

function Race:playerFinish(player)
	if not isElement(player) or player.type ~= "player" then
		return false
	end	
	-- TODO: Не удалять игрока из гонки сразу, отображать экран конца гонки
	self:removePlayer(player)
end

-- Время вышло
function Race:onTimeout()
	outputDebugString("Race timeout")

	-- Принудительно финишировать всем игрокам
	for i, player in ipairs(self.players) do
		self:playerFinish(player)
	end
end

---- Обработчики событий МТА
-- Каждый обработчик должен иметь следующее имя:
-- <eventName>Handler, где eventName - название события
-- Например: "onPlayerQuitHandler"
-- source - первый аргумент обработчика

-- Игрок вышел из автомобиля
function Race:onVehicleStartExitHandler(vehicle, player)
	-- TODO: Запустить таймер, показать предупреждение
	self:playerFinish(player)
end

-- Игрок вышел с сервера
function Race:onPlayerQuitHandler(player)
	self:removePlayer(player)
end