--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"); you may not use this file except in compliance with
-- the License.  You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--

local kong = kong
local ffi = require "ffi"
local zlib = require("zlib")
local cjson = require "cjson"
local concat = table.concat
local system_constants = require "lua_system_constants"

-- skywalking 8 start
local SegmentRef = require("kong.plugins.skywalking.segment_ref")
local CONTEXT_CARRIER_KEY = 'sw8'
-- skywalking 8 end

local O_CREAT = system_constants.O_CREAT()
local O_WRONLY = system_constants.O_WRONLY()
local O_APPEND = system_constants.O_APPEND()
local S_IRUSR = system_constants.S_IRUSR()
local S_IWUSR = system_constants.S_IWUSR()
local S_IRGRP = system_constants.S_IRGRP()
local S_IROTH = system_constants.S_IROTH()

local oflags = bit.bor(O_WRONLY, O_CREAT, O_APPEND)

local mode = bit.bor(S_IRUSR, S_IWUSR, S_IRGRP, S_IROTH)

local C = ffi.C

ffi.cdef [[
int write(int fd, const void * ptr, int numbytes);
]]

-- fd tracking utility functions
local file_descriptors = {}

local LogfilesHandler = {}

LogfilesHandler.PRIORITY = 9
LogfilesHandler.VERSION = "0.1.0"



function LogfilesHandler:access(conf)
    kong.ctx.shared.access_time = ngx.now()
end

function LogfilesHandler:body_filter(conf)

    local ctx = ngx.ctx
    local chunk, eof = ngx.arg[1], ngx.arg[2]
    local uncompress

    ctx.rt_body_chunks = ctx.rt_body_chunks or {}
    ctx.rt_body_chunk_number = ctx.rt_body_chunk_number or 1

    if eof then
        local chunks = concat(ctx.rt_body_chunks)

        local encoding = kong.response.get_header("Content-Encoding")
        if encoding == "gzip" then
            uncompress = zlib.inflate()(chunks)
        end

        kong.ctx.shared.respbody = uncompress or chunks
        ngx.arg[1] = chunks
    else
        ctx.rt_body_chunks[ctx.rt_body_chunk_number] = chunk
        ctx.rt_body_chunk_number = ctx.rt_body_chunk_number + 1
        ngx.arg[1] = nil
    end
end

function LogfilesHandler:log(conf)
    -- local message = serialize(ngx)
    local data
    data = ngx.req.get_body_data()
	
	-- skywalking 8 start
	local trace_id ="";
	local propagatedContext = ngx.req.get_headers()[CONTEXT_CARRIER_KEY]
	if propagatedContext ~= nil then
		local ref = SegmentRef.fromSW8Value(propagatedContext)
		if ref ~= nil then
			trace_id = ref.trace_id
		end
	end
	-- skywalking 8 end
	
    local logs = {
        client_ip = kong.client.get_ip(),
        client_forwarded_ip = kong.client.get_forwarded_ip(),
		trace_id = trace_id,
        request_scheme = kong.request.get_scheme(),
        request_host = kong.request.get_host(),
        request_method = kong.request.get_method(),
        request_path = kong.request.get_path(),
        request_headers = kong.request.get_headers(),
        request_sunmi_id = kong.ctx.shared.sunmi_id,
        request_sunmi_shopid = kong.ctx.shared.sunmi_shopid,
        request_raw_body = data,
        response_status = kong.response.get_status(),
        response_headers = kong.response.get_headers(),
        response_body = kong.ctx.shared.respbody,
        process_time = 0,
        time = 0
    }

    if kong.ctx.shared.access_time ~= nil then
        logs.process_time = (ngx.now() - kong.ctx.shared.access_time)
        logs.time = kong.ctx.shared.access_time
    end

    local msg = cjson.encode(logs) .. "\n"

    local fd = file_descriptors[conf.path]

    if fd and conf.reopen then
        C.close(fd)
        file_descriptors[conf.path] = nil
        fd = nil
    end

    if not fd then
        fd = C.open(conf.path, oflags, mode)
        if fd < 0 then
            local errno = ffi.errno()
            ngx.log(ngx.ERR, "[logfiles] failed to open the file: ", ffi.string(C.strerror(errno)))
        else
            file_descriptors[conf.path] = fd
        end
    end

    C.write(fd, msg, #msg)

end

return LogfilesHandler