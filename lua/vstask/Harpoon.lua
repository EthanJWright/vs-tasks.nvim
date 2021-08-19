local InUse = {}

function Harpoon_process(command)
    if InUse[command] == nil then
      InUse[command] = #InUse + 1
    end
    local term_number = InUse[command]
    require("harpoon.term").sendCommand(term_number, command)
    require("harpoon.term").gotoTerminal(term_number)
end

return { Process = Harpoon_process }
