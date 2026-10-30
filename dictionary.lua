local Dictionary = {}
Dictionary.__index = Dictionary

-- 內部簡單的日誌函數，模擬 Perl 中的 Logger
local function _log(level, msg)
    local levels = {
        ERROR = ngx.ERR,
        WARNING = ngx.WARN,
        DEBUG = ngx.DEBUG,
        INFO = ngx.INFO
    }
    ngx.log(levels[level] or ngx.ERR, msg)
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
    self.loaded_files = {} -- 防止循環引用與重複載入
    self.current_vendor_name = nil -- 當前廠商名稱
    return self
end

-- 已知類型的集合 (RADIUS / Diameter 常用類型)
local KNOWN_TYPES = {
    ["OctetString"] = true,
    ["String"]      = true,
    ["Integer"]     = true,
    ["Time"]        = true,
    -- Diameter
    ["IPAddress"]   = true,
    ["Unsigned32"]  = true,
    ["Unsigned8"]   = true,
    ["Unsigned16"]  = true,
    ["Float32"]     = true,
    ["Float64"]     = true,
    ["DiameterIdentity"] = true,
    ["DiameterURI"]     = true,
}

-- 檢查類型是否為已知的 RADIUS/Diameter 類型
function Dictionary:is_known_type(type)
    return KNOWN_TYPES[type] == true
end

-- 解析 flags：將字串 flags（如 "m", "p", "c"）轉換為數值
function Dictionary:resolve_flags(name, vendor, flags)
    if not flags or flags == "" then
        return 0
    end
    local result = 0
    local flag_map = {
        ["m"] = 1,  -- mandatory
        ["p"] = 2,  -- protected
        ["c"] = 4,  -- vendor-specific
        ["t"] = 8,  -- tunnel
    }
    for i = 1, #flags do
        local f = flags:sub(i, i)
        if flag_map[f] then
            result = result + flag_map[f]
        end
    end
    return result
end

function Dictionary:load_file(filename, base_dir)
    local trimmed_name = filename:match("^%s*(.-)%s*$")
    if not trimmed_name then
        _log("ERROR", "Filename is empty or only whitespace")
        return nil
    end

    -- 2. 計算完整路徑
    local full_path = trimmed_name
    if base_dir and not trimmed_name:match("[/\\]") then
        local clean_base = base_dir:sub(1, -1) == "/" and base_dir or base_dir .. "/"
        full_path = clean_base .. trimmed_name
    end

    _log("INFO", "load_file: filename='" .. trimmed_name .. "', base_dir='" .. tostring(base_dir) .. "', full_path='" .. full_path .. "'")

    -- 3. 檢查是否已載入
    if self.loaded_files[full_path] then
        _log("INFO", "Skipping already loaded file: " .. full_path)
        return true
    end
    self.loaded_files[full_path] = true

    -- 4. 開啟檔案
    local file = io.open(full_path, "r")
    if not file then
        _log("ERROR", "Could not open dictionary file '" .. full_path .. "'")
        return nil
    end

    -- 5. 計算當前目錄，供 $INCLUDE 使用
    local new_dir = full_path:match("^(.*[/\\])") or "./"
    _log("INFO", "Calculated new_dir: '" .. new_dir .. "'")

    self:load_handle(file, "file " .. full_path, new_dir)
    file:close()
    return true
end

function Dictionary:load_handle(file, file_info, new_dir)
    _log("INFO", "Loading handle for: " .. file_info)

    while true do
        local l = file:read("*l")
        if not l then break end

        -- 1. 移除註解
        l = l:gsub("#.*$", "")

        -- 2. 修剪前後空白
        l = l:match("^%s*(.-)%s*$")

        if not l or l == "" then goto continue end

        -- 3. ATTRIBUTE pattern
        local name, num, atype, flag1, flag2 = l:match("^ATTRIBUTE%s+(%S+)%s+(%d+)%s+(%S*)%s*(%S*)%s*$")
        if name then
            if flag2 and flag2 ~= "" then
                _log("WARNING", "Ignoring trailing garbage '" .. flag2 .. "' in Diameter dictionary " .. file_info)
            end
            local vendor_id = 0
            if self.current_vendor_name and self.VendorName[self.current_vendor_name] then
                vendor_id = self.VendorName[self.current_vendor_name][2]
            end
            self:defineAttr(name, atype, tonumber(num), vendor_id, flag1)
            goto continue
        end

        -- 4. VENDORATTR pattern
        local v_key, v_name, v_attrnum, v_type, v_flag1, v_flag2 = l:match("^%s*(%S+)%s+(%S+)%s+(%d+)%s+(%S+)%s*(%S*)%s*$")
        if v_key and (v_key == "VENDORATTR" or v_key == "VSA" or v_key == "VENDOR_ATTRIBUTE") then
            _log("DEBUG", "VENDORATTR match: key="..v_key..", name="..v_name..", num="..v_attrnum..", type="..v_type..", flag1="..v_flag1)
            local vendor = v_name
            if self.VendorName[v_name] then
                vendor = self.VendorName[v_name][2]
            end

            local attr_num = tonumber(v_attrnum)
            if v_attrnum:sub(1,1) == "0" then
                attr_num = tonumber(v_attrnum, 8)
            end

            if v_flag2 and v_flag2 ~= "" then
                _log("WARNING", "Ignoring trailing garbage '" .. v_flag2 .. "' in Diameter dictionary " .. file_info)
            end

            local v_name_internal = v_name
            local v_attrnum_internal = v_attrnum
            local v_type_internal = v_type
            local v_flag1_internal = v_flag1
            local v_garbage_internal = v_flag2

            if v_garbage_internal and v_garbage_internal ~= "" then
                _log("WARNING", "Ignoring trailing garbage '" .. v_garbage_internal .. "' in Diameter dictionary " .. file_info)
            end

            local vendor_final = v_name_internal
            if self.VendorName[v_name_internal] then
                vendor_final = self.VendorName[v_name_internal][2]
            end

            local attr_num_final = tonumber(v_attrnum_internal)
            if v_attrnum_internal:sub(1,1) == "0" then
                attr_num_final = tonumber(v_attrnum_internal, 8)
            end

            self:defineAttr(v_name, v_type, attr_num_final, vendor_final, v_flag1)
            goto continue
        end

        -- 5. VALUE pattern
        local val_name, val_num = l:match("^VALUE%s+(%S+)%s+(%S+)%s+(%d+)$")
        if val_name then
            self:defineVal(val_name, val_num, tonumber(val_num))
            goto continue
        end

        -- 6. VENDOR pattern (排除 BEGIN-VENDOR / END-VENDOR)
        local vend_name, vend_num, vend_extra = l:match("^%s*VENDOR%s+(%S+)%s+(%S+)%s*(.*)$")
        if vend_name then
            -- 確認不是 BEGIN-VENDOR 或 END-VENDOR
            if vend_name ~= "VENDOR" or (not l:match("^BEGIN-VENDOR") and not l:match("^END-VENDOR")) then
                self:defineVendor(vend_name, tonumber(vend_num), vend_extra)
            end
            goto continue
        end

        -- 7. $INCLUDE pattern
        local include_file = l:match("^%s*%$INCLUDE%s+(%S+)%s*$")
        if include_file then
            self:load_file(include_file, new_dir)
            goto continue
        end

        -- 8. BEGIN-VENDOR pattern
        local begin_name = l:match("^%s*BEGIN%-VENDOR%s+(%S+)%s*$")
        if begin_name then
            self.current_vendor_name = begin_name
            goto continue
        end

        -- 9. END-VENDOR pattern
        local end_name = l:match("^%s*END%-VENDOR%s+(%S+)%s*$")
        if end_name then
            self.current_vendor_name = nil
            goto continue
        end

        -- 如果沒匹配到任何模式
        _log("ERROR", "Bad format in dictionary " .. file_info .. " at line: '" .. l .. "'")

        ::continue::
    end
    return true
end

function Dictionary:defineAttr(name, type, number, vendor, flags)
    if not self:is_known_type(type) then
        _log("WARNING", "Bad type " .. type .. " for attribute " .. name .. " in dictionary. Encoding and decoding this attribute may fail.")
    end
    local resolvedflags = self:resolve_flags(name, vendor, flags)
    local a = {name, type, number, vendor, resolvedflags}
    self.AttrName[name] = a
    self.AttrNum[vendor] = self.AttrNum[vendor] or {}
    self.AttrNum[vendor][number] = a
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
    if self.ValName[attrname] and self.ValNum[attrname][valnum] then
        return self.ValName[attrname][valnum]
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
