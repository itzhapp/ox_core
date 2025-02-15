AddEventHandler('playerEnteredScope', function(data)
    local source = tonumber(data['for'], 10)
    local target = tonumber(data.player, 10)
    local player = Ox.GetPlayer(source)

    if player then
        local inScope = player:getPlayersInScope()
        inScope[target] = true
    end
end)

AddEventHandler('playerLeftScope', function(data)
    local source = tonumber(data['for'], 10)
    local target = tonumber(data.player, 10)
    local player = Ox.GetPlayer(source)

    if player then
        local inScope = player:getPlayersInScope()
        inScope[target] = nil
    end
end)

local npwd = GetExport('npwd')
local appearance = GetExport('ox_appearance')
local db = require 'server.player.db'
local StatusRegistry = require 'server.status.registry'

---@param data number | { firstName: string, lastName: string, gender: string, date: number }
RegisterNetEvent('ox:selectCharacter', function(data)
    local player = Ox.GetPlayer(source) --[[@as OxPlayerInternal?]]

    if not player then return end

    ---@type CharacterProperties
    local character

    if type(data) == 'table' then
        local phoneNumber = npwd and npwd:generatePhoneNumber() or nil
        local stateid = Ox.GenerateStateId()

        character = {
            firstname = data.firstName,
            lastname = data.lastName,
            charid = db.createCharacter(player.userid, stateid, data.firstName, data.lastName, data.gender, data.date, phoneNumber),
            stateid = stateid
        }
    elseif type(data) == 'number' and data <= Shared.CHARACTER_SLOTS then
        character = player.characters[data]
    else
        error(('ox:selectCharacter received invalid slot. Received %s'):format(data))
    end

    player.characters = nil
    player.name = ('%s %s'):format(character.firstname, character.lastname)
    player.charid = character.charid
    player.stateid = character.stateid or db.updateStateId(Ox.GenerateStateId(), player.charid)
    player.firstname = character.firstname
    player.lastname = character.lastname
    player.ped = GetPlayerPed(player.source)

    local groups = db.selectCharacterGroups(player.charid)

    if groups then
        for i = 1, #groups do
            local name, grade in groups[i]
            local group = Ox.GetGroup(name)

            if group then
                group:add(player, grade)
            end
        end
    end

    local licenses = db.selectCharacterLicenses(player.charid)

    if licenses then
        local playerLicenses = player:getLicenses()

        for i = 1, #licenses do
            local license = licenses[i]
            playerLicenses[license.name] = license
            license.name = nil
        end
    end

    local cData = db.selectCharacterData(character.charid)
    local state = player:getState()
    local coords = character.x and vec4(character.x, character.y, character.z, character.heading)

    if appearance then appearance:load(player.source, player.charid) end

    TriggerClientEvent('ox:loadPlayer', player.source, coords, {
        firstname = player.firstname,
        lastname = player.lastname,
        name = player.name,
        userid = player.userid,
        charid = player.charid,
        stateid = player.stateid,
        groups = player:getGroups(),
    }, cData.health, cData.armour, cData.gender)

    state:set('dead', player:get('isDead'), true)
    state:set('name', player.name, true)

    player:set('dateofbirth', cData.dateofbirth, true)
    player:set('gender', cData.gender, true)
    player:set('phoneNumber', cData.phoneNumber, true)

    cData.statuses = json.decode(cData.statuses)

    for name, status in pairs(StatusRegistry) do
        player:setStatus(name, cData.statuses?[name] or status.default)
    end

    for _, load in pairs(LoadResource) do
        load(player)
    end

    TriggerEvent('ox:playerLoaded', player.source, player.userid, player.charid)
end)

RegisterNetEvent('ox:deleteCharacter', function(slot)
    if type(slot) == 'number' and slot <= Shared.CHARACTER_SLOTS then
        slot += 1
        local player = Ox.GetPlayer(source)

        if not player then return end

        local charid = player.characters[slot]?.charid

        if charid and db.deleteCharacter(charid) then
            if appearance then appearance:save(charid) end

            table.remove(player.characters, slot)

            return TriggerEvent('ox:characterDeleted', player.source, player.userid, charid)
        end
    end

    error(('ox:deleteCharacter received invalid slot. Received %s'):format(slot))
end)

RegisterNetEvent('ox:playerDeath', function(state)
    local player = Ox.GetPlayer(source)

    if player and player.charid then
        player:set('isDead', state)
    end
end)

RegisterNetEvent('ox:setPlayerInService', function(job)
    local player = Ox.GetPlayer(source)

    if player and player.charid then
        if job and player:getGroup(job) then
            return player:set('inService', job, true)
        end

        player:set('inService', false, true)
    end
end)

