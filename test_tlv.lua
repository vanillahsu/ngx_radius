local Dictionary = require("dictionary")

-- Mock ngx for unit testing outside of OpenResty environment
local ngx = {
    ERR = "ERR",
    WARN = "WARN",
    DEBUG = "DEBUG",
    INFO = "INFO",
    log = function(level, msg)
        print("[MOCK NGX LOG] [" .. level .. "] " .. msg)
    end
}
-- Inject ngx into the global environment so dictionary.lua can find it
_G.ngx = ngx

local function test()
    print("Starting TLV unit tests...")

    -- 1. Test Normal TLV flow
    print("\n--- Test 1: Normal TLV flow ---")
    local dict1 = Dictionary.new()
    local content1 = [[
VENDOR TestVendor 12345
BEGIN-VENDOR TestVendor
ATTRIBUTE Attr1 1 tlv
BEGIN-TLV Attr1
ATTRIBUTE SubAttr1 1 byte
END-TLV Attr1
END-VENDOR TestVendor
]]
    local f1 = io.open("test_tlv_normal.tmp", "w")
    f1:write(content1)
    f1:close()

    dict1:load_file("test_tlv_normal.tmp")

    local attr = dict1:attrByName("Attr1")
    if attr and attr[1] == "Attr1" and attr[4] == 12345 then
        print("✅ Test 1 Passed: Attr1 found with correct vendor")
    else
        print("❌ Test 1 Failed: Attr1 not found or incorrect")
    end
    os.remove("test_tlv_normal.tmp")


    -- 2. Test Mismatched END-TLV
    print("\n--- Test 2: Mismatched END-TLV ---")
    local dict2 = Dictionary.new()
    local content2 = [[
VENDOR TestVendor 12345
BEGIN-VENDOR TestVendor
ATTRIBUTE Attr2 2 tlv
BEGIN-TLV Attr2
ATTRIBUTE SubAttr2 1 byte
END-TLV WrongName
END-VENDOR TestVendor
]]
    local f2 = io.open("test_tlv_mismatch.tmp", "w")
    f2:write(content2)
    f2:close()

    dict2:load_file("test_tlv_mismatch.tmp")
    print("✅ Test 2: Check completed (Check stdout for 'Mismatch' warning)")
    os.remove("test_tlv_mismatch.tmp")


    -- 3. Test Auto-close TLV on END-VENDOR
    print("\n--- Test 3: Auto-close TLV on END-VENDOR ---")
    local dict3 = Dictionary.new()
    local content3 = [[
VENDOR TestVendor 12345
BEGIN-VENDOR TestVendor
ATTRIBUTE Attr3 3 tlv
BEGIN-TLV Attr3
ATTRIBUTE SubAttr3 1 byte
END-VENDOR TestVendor
]]
    local f3 = io.open("test_tlv_autoclose.tmp", "w")
    f3:write(content3)
    f3:close()

    dict3:load_file("test_tlv_autoclose.tmp")
    print("✅ Test 3: Check completed (Check stdout for 'Auto-closing' warning)")
    os.remove("test_tlv_autoclose.tmp")

    print("\nAll TLV unit tests finished.")
end

test()
