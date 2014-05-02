--
-- Module for managing notebook container instances running with the docker module
--
-- author: Steve Chan sychan@lbl.gov
--
-- Copyright 2013 The Regents of the University of California,
--                Lawrence Berkeley National Laboratory
--                United States Department of Energy
--          	 The DOE Systems Biology Knowledgebase (KBase)
-- Made available under the KBase Open Source License
--

local M = {}

local docker = require('docker')
local json = require('json')
local p = require('pl.pretty')
local lfs = require('lfs')
local httplib = require("resty.http")
local httpclient = httplib:new()

-- This is the repository name, can be set by whoever instantiates a notelauncher
M.repository_image = 'sychan/narrative'
-- This is the tag to use, defaults to latest
M.repository_version = 'latest'
-- This is the port that should be exposed from the container, the service in the container
-- should have a listener on here configured
M.private_port = 8888
-- This is the path to the syslog Unix socket listener in the host environment
-- it is imported into the container via a Volumes argument
M.syslog_src = '/dev/log'

-- Base URL that the non-blocking docker remote api calls should use
M.docker_remote_url = 'http://127.0.0.1:65000'

-- Non-blocking version of the docker.client.containers() method using
-- resty.http
local function containers(arg)
   local req = {
      url = M.docker_remote_url .. "/containers/json",
      method = "GET"
   }
   -- ngx.log( ngx.ERR, p.write(req))
   local ok, code,headers,status,body = httpclient:request(req)
   if ok and code >= 200 and code < 300 then
      return ok, json.decode(body)
   else
      return nil, body
   end
end

-- Non-blocking version of the docker.client.containers() method using
-- resty.http
-- pass in any optional args to be passed in via the GET
local function inspect_container(arg)
   assert(arg.id ~= nil, "id argument must be set")
   local req = {
      url = string.format("%s/containers/%s/json",M.docker_remote_url, arg.id),
      method = "GET"
   }
   local ok, code,headers,status,body = httpclient:request(req)
   if ok and code >= 200 and code < 300 then
      return ok, json.decode(body)
   else
      return nil, body
   end
end

-- Non-blocking version of the docker.client.create_container() method using
-- resty.http
local function create_container(arg)
   assert(arg.body ~= nil, "body argument must be set")
   local req = {
      url = M.docker_remote_url .. "/containers/create",
      method = "POST"
   }
   local ok, code,headers,status,body = httpclient:request(req)
   if ok and code >= 200 and code < 300 then
      return ok, json.decode(body)
   else
      return nil, body
   end
end

-- Non-blocking version of the docker.client.start_container() method using
-- resty.http
-- pass in any optional args to be passed in via the GET
local function start_container(arg)
   assert(arg.id ~= nil, "id argument must be set")
   local req = {
      url = string.format("%s/containers/%s/start",M.docker_remote_url,arg.id),
      method = "POST"
   }
   local ok, code,headers,status,body = httpclient:request(req)
   if ok and code >= 200 and code < 300 then
      return ok, json.decode(body)
   else
      return nil, body
   end
end

-- Non-blocking version of the docker.client.stop_container() method using
-- resty.http
-- pass in any optional args to be passed in via the GET
local function stop_container(arg)
   assert(arg.id ~= nil, "id argument must be set")
   local req = {
      url = string.format("%s/containers/%s/stop",M.docker_remote_url,arg.id),
      method = "POST"
   }
   local ok, code,headers,status,body = httpclient:request(req)
   if ok and code >= 200 and code < 300 then
      return ok, json.decode(body)
   else
      return nil, body
   end
end

-- Non-blocking version of the docker.client.remove_container() method using
-- resty.http
-- pass in any optional args to be passed in via the GET
local function remove_container(arg)
   assert(arg.id ~= nil, "id argument must be set")
   local req = {
      url = string.format("%s/containers/%s",M.docker_remote_url,arg.id),
      method = "DELETE"
   }
   local ok, code,headers,status,body = httpclient:request(req)
   if ok and code >= 200 and code < 300 then
      return ok, nil
   else
      return nil, body
   end
end

--
--  Query the docker container for a list of containers and
-- return a list of the container names that have listeners on
-- port 8888. Keyed on container name, value is IP:Port that can
-- be fed into an nginx proxy target
local function get_notebooks()
   local ok, res, code,headers,status,body
   ok,res = containers()
   -- ngx.log( ngx.ERR, string.format("resty containers() body result: %s",p.write(res)))
   local portmap = {}
   if ok then
      for index,container in pairs(res) do
	 -- we only care about containers matching repository_image and listening on the proper port
	 first,last = string.find(container.Image,M.repository_image)
	 if first == 1 then
	    name = string.sub(container.Names[1],2,-1)
	    portmap[name]={}
	    for i, v in pairs(container.Ports) do
	       if v.PrivatePort == M.private_port then
		  portmap[name] = string.format("127.0.0.1:%u", v.PublicPort)
	       end
	    end
	 end
      end
      return portmap
   else
      local msg = string.format("Failed to fetch list of containers: %s",p.write(res))
      ngx.log(ngx.ERR,msg)
      error(msg)
   end
end

--
--    Actually launch a new docker container.
--
local function launch_notebook( name )
   -- don't wrap this in a pcall, if it fails let it propagate to
   -- the caller
   portmap = get_notebooks()
   assert(portmap[name] == nil, "Notebook by this name already exists: " .. name)
   local conf = docker.config()
   local bind_syslog = nil
   conf.Image = string.format("%s:%s",M.repository_image,M.repository_version)
   conf.Cmd={name}
   conf.PortSpecs = {tostring(M.private_port)}
   ngx.log(ngx.INFO,string.format("Spinning up instance of %s on port %d",conf.Image, M.private_port))
   -- we wrap the next call in pcall because we want to trap the case where we get an
   -- error and try deleting the old container and creating a new one again
   local ok,res = pcall(docker.client.create_container, docker.client, { payload = conf, name = name})
   if not ok and res.response.status >= 409 then
      -- conflict, try to delete it and then create it again
      ngx.log(ngx.ERR,string.format("conflicting notebook, removing notebook named: %s",name))   
      -- ok, res = pcall( docker.client.remove_container, docker.client, { id = name })
      ok, res = remove_container{ id = name }
      ngx.log(ngx.ERR,string.format("response from remove_container: %s", p.write(res)))
      -- ignore the response and retry the create, and if it still errors, let that propagate
      ok, res = pcall(docker.client.create_container, docker.client, { payload = conf, name = name})
   end
   if ok then
      assert(res.status == 201, "Failed to create container: " .. json.encode(res.body))
      local id = res.body.Id
      if M.syslog_src then
	 -- Make sure it exists and is writeable
	 local stat = lfs.attributes(M.syslog_src)
	 if stat ~= nil and stat.mode == 'socket' then
	    bind_syslog = { string.format("%s:%s",M.syslog_src,"/dev/log") }
	    --ngx.log(ngx.ERR,string.format("Binding %s in container %s", bind_syslog[1], name))
	 else
	    --ngx.log(ngx.ERR,string.format("%s is not writeable, not mounting in container %s",M.syslog_src, name))
	 end
      end
      if bind_syslog ~= nil then
	 res = docker.client:start_container{ id = id, payload = { PublishAllPorts = true, Binds = bind_syslog }}
      else
	 res = docker.client:start_container{ id = id, payload = { PublishAllPorts = true }}
      end      
      assert(res.status == 204, "Failed to start container " .. id .. " : " .. json.encode(res.body))
      -- get back the container info to pull out the port mapping
      -- res = docker.client:inspect_container{ id=id}
      ok, res = inspect_container{ id=id}
      -- ngx.log( ngx.ERR,"non-blocking inspect_container results: " .. p.write(res))
      assert(ok, "Could not inspect new container: " .. id)
      local ports = res.NetworkSettings.Ports
      local ThePort = string.format("%d/tcp", M.private_port)
      assert( ports[ThePort] ~= nil, string.format("Port binding for port %s not found!",ThePort))
      return(string.format("%s:%d","127.0.0.1", ports[ThePort][1].HostPort))
   else
      local msg = "Failed to create container: " .. p.write(res)
      ngx.log(ngx.ERR,msg)
      error(msg)
   end
end

--
--    Kill and remove an existing docker container.
--
local function remove_notebook( name )
   local portmap = get_notebooks()
   if portmap[name] == nil then
      return nil,  "Notebook by this name does not exist: " .. name
   end
   local id = string.format('/%s',name)
   --ngx.log(ngx.INFO,string.format("removing notebook named: %s",id))
   local res = docker.client:stop_container{ id = id }
   ngx.log(ngx.ERR,string.format("response from stop_container: %d : %s",res.status,res.body))
   if res.status ~= 204 then
      return nil, "Failed to stop container: " .. json.encode(res.body)
   end
   ok, res = remove_container{ id = id}
   ngx.log(ngx.ERR,string.format("response from remove_container: %s : %s",ok, p.write(res)))
   if not ok then
      return ok, "Failed to remove container " .. id .. " : " .. json.encode(res)
   end
   return true
end

M.docker = docker
M.get_notebooks = get_notebooks
M.launch_notebook = launch_notebook
M.remove_notebook = remove_notebook
return M

