-- Script to integrate with Romacs
-- Handles console too
-- It also exposes the following functions
--   _G.send("(something 123)") ; To send a message to Romacs
--                              ; Note: It must be an S-expression as documented in Romacs
--   _G.websocket ; The websocket connected to Romacs

assert(WebSocket, "Your exploit doesn't have WebSockets and so: it can't connect to Romacs")

local websocket = WebSocket.connect("ws://localhost:1003")
_G.websocket = websocket

print("Emacs integration is running!")

local function send(message)
    if _G.websocket then
        _G.websocket:Send(message)
    end
end
_G.send = send

websocket.OnMessage:Connect(function(message)
    local run_code = loadstring(message)
    local success, error_message = pcall(run_code)
    if not success then
        error(error_message)
    end
end)

websocket.OnClose:Connect(function()
    print("Emacs integration stopped.")
    _G.websocket = nil
end)

-- console protocol
local LogService = game:GetService("LogService")
local message_template = "(console (:type %s :message \"%s\"))"

do
    local connection;

    connection = LogService.MessageOut:Connect(function(msg, msgType)
        _G.send(message_template:format(msgType.Name, msg))
    end)

    websocket.OnClose:Connect(function()
        connection:Disconnect()
    end)
end