local Dictionary = {}
Dictionary.__index = Dictionary

-- 內部簡單的日誌函數，模擬 Perl 中的 Logger
local function _log(level, msg)
    print(string.format("[%s] %s", level, msg))
end

function Dictionary.new()
    local self = setmetatable({}, Dictionary)
    -- 初始化數據結構
    self.AttrNum = {}    -- AttrNum{vendornum}->{attrnum}
    self.AttrName = {}   -- AttrName{attrname}
    self.ValName = {}    -- ValName{attrname}->{valuenum}
    self.ValNum = {}     -- ValNum{attrname}->{valuenum}
    self.VendorName = {} -- VendorName{vendorname}
    self.VendorNum = {}  -- VendorNum{vendornum}
    return self
end

-- 模擬 Perl 的 is_known_type (需被子類別覆寫)
function Dictionary:is_known_type(type)
    _log("ERROR", "Someone forgot to override Dictionary:is_known_type")
    return false
end

-- 模擬 Perl 的 resolve_flags (需被子類يش覆寫)
function Dictionary:resolve_flags(name, vendor, flags)
    _log("ERROR", "Someone forgot to override Dictionary:resolve_flags")
    return 0
end

function Dictionary:load_file(filename)
    local file = io.open(filename, "r")
    if not file then
        _log("ERROR", "Could not open dictionary file '" .. filename .. "'")
        return nil
    end
    self:load_handle(file, "file " .. filename)
    file:close()
    return true
end

function Dictionary:load_handle(handle, handledesc)
    while true do
        local l = handle:read("*l")
        if not l then break end

        -- 移除註解與空白
        l = l:gsub("#.*$", ""):gsub("^%s*(.-)%s*$", "%1")
        if l == "" then goto continue end

        -- 1. ATTRIBUTE pattern: ATTRIBUTE name number type [flags]
        local name, num, atype, flag1, flag2 = l:match("^ATTRIBUTE%s+(%S+)%s+(%d+)%s+(%S+)%s*(%S*)%s*(%S*)")
        if name then
            flag2 = flag2 or ""
            if flag2 ~= "" then
                _log("WARNING", "Ignoring trailing garbage '" .. flag2 .. "' in Diameter dictionary " .. handledesc)
            end
            self:defineAttr(tonumber(num), 0, name, atype, flag1)
            goto continue
        end

        -- 2. VENDORATTR pattern: VENDORATTR|VSA|VENDOR_ATTRIBUTE vendornum name number type [flags]
        local v_key, v_name, v_attrnum, v_type, v_flag1, v_flag2, v_garbage = l:match("^(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s*(%S*)%s*(%S*)")
        if v_key == "VENDORATTR" or v_key == "VSA" or v_key == "VENDOR_ATTRIBUTE" then
            print("DEBUG: VENDORATTR match: key="..v_key..", name="..v_name..", num="..v_attrnum..", type="..v_type..", flag1="..v_flag1)
            local vendor = v_name
            -- 如果 vendor 是名稱，嘗試從 VendorName 查表轉為數字
            if self.VendorName[v_name] then
                vendor = self.VendorName[v_name][2]
            end

            -- 處理八進制 (Perl 的 oct 功能)
            local attr_num = tonumber(v_attrnum)
            if v_attrnum:sub(1,1) == "0" then
                attr_num = tonumber(v_attrnum, 8)
            end

            v_flag2 = v_flag2 or ""
            v_garbage = v_garbage or ""

            if v_garbage ~= "" then
                _log("WARNING", "Ignoring trailing garbage '" .. v_garbage .. "' in Diameter dictionary " .. handledesc)
            end

            self:defineAttr(tonumber(attr_num), tonumber(vendor), v_type, v_flag1)
            goto continue
        end

        -- 3. VALUE pattern: VALUE attrname valname valnum
        local val_attr, val_name, val_num = l:match("^VALUE%s+(%S+)%s+(%S+)%s+(%d+)")
        if val_attr then
            self:defineVal(val_attr, val_name, tonumber(val_num))
            goto continue
        end

        -- 4. VENDOR pattern: VENDOR name number [extra]
        local vend_name, vend_num, vend_extra = l:match("^VENDOR%s+(%S+)%s+(%S+)%s*(.*)")
        if not vend_name then
            vend_name, vend_num, vend_extra = l:match("^VENDOR_CODE%s+(%S+)%s+(%S+)%s*(.*)")
        end

        if vend_name then
            self:defineVendor(vend_name, tonumber(vend_num), vend_extra)
            goto continue
        end

        -- 如果沒匹配到任何模式
        _log("ERROR", "Bad format in dictionary " .. handledesc .. " at line: " .. l)

        ::continue::
    end
    return true
end

function Dictionary:defineAttr(number, vendor, name, type, flags)
    if not self:is_known_type(type) then
        _log("WARNING", "Bad type " .. type .. " for attribute " .. name .. " in dictionary. Encoding and decoding this attribute may fail.")
    end

    local resolvedflags = self:resolve_flags(name, vendor, flags)
    vendor = vendor or 0
    local a = {name, type, number, vendor, resolvedflags}

    self.AttrNum[vendor] = self.AttrNum[vendor] or {}
    self.AttrNum[vendor][number] = a
    self.AttrName[name] = a

    return a
end

function Dictionary:defineVal(attrname, valname, value)
    local v = {valname, value, attrname}
    self.ValName[attrname] = self.ValName[attrname] or {}
    self.ValName[attrname][valname] = v
    self.ValNum[attrname] = self.ValNum[attrname] or {}
    self.ValNum[attrname][value] = v
    return v
end

function Dictionary:defineVendor(name, number, ...)
    local extras = {...}
    local a = {name, number}
    for i, v in ipairs(extras) do table.insert(a, v) end

    self.VendorNum[number] = a
    self.VendorName[name] = a
    return a
end

function Dictionary:attrByName(name)
    return self.AttrName[name]
end

function Dictionary:attrByNum(number, vendor)
    vendor = tonumber(vendor) or 0
    if self.AttrNum[vendor] and self.AttrNum[vendor][number] then
        return self.AttrNum[vendor][number]
    end
    return {string.format("Attr-%s-%s", vendor, number), 'OctetString', number, vendor}
end

function Dictionary:valByNum(attrname, valnum)
    if self.ValNum[attrname] and self.ValNum[attrname][valnum] then
        return self.ValNum[attrname][valnum]
    end
    return nil
end

function Dictionary:valByName(attrname, valname)
    -- 處理 0x 開頭的十六進制轉換
    local hex_match = valname:match("^0x([0-9a-fA-F]+)$")
    if hex_match then
        valname = tonumber(hex_match, 16)
    end

    if self.ValName[attrname] and self.ValName[attrname][valname] then
        return self.ValName[attrname][valname]
    end
    return nil
end

function Dictionary:valuesForAttribute(attrname)
    local res = {}
    if self.ValName[attrname] then
        for k in pairs(self.ValName[attrname]) do
            table.insert(res, k)
        end
    end
    table.sort(res)
    return res
end

function Dictionary:vendorNums()
    local res = {}
    for k in pairs(self.VendorNum) do
        table.insert(res, k)
    end
    table.sort(res)
    return res
end

function Dictionary:vendorByNum(vendornum)
    if self.VendorNum[vendornum] then
        return self.VendorNum[vendornum]
    end
    return nil
end

function Dictionary:vendorByName(vendorname)
    if self.VendorName[vendorname] then
        return self.VendorName[vendorname]
    end
    return nil
end

return Dictionary
