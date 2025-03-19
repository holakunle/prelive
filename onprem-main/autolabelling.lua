-- Initialize global table to track active labels with their timestamps
if activeLabels == nil then
    activeLabels = {}
  end
  
  -- Helper function to get current time (using Lua's os.time for simplicity)
  local function getCurrentTime()
    local time = os.time()
    print("Current time (os.time): " .. time)
    return time
  end
  
  -- Cleanup function to remove expired labels
  local function cleanupExpiredLabels()
    local currentTime = getCurrentTime()
    if not currentTime then
      print("Skipping cleanup due to time fetch failure")
      return
    end
    print("Running cleanup at " .. currentTime)
    if next(activeLabels) == nil then
      print("No active labels to clean")
      return
    end
  
    for studyId, timestamps in pairs(activeLabels) do
      print("Checking study " .. studyId .. " in activeLabels")
      if timestamps.NEW then
        local age = currentTime - timestamps.NEW
        print("NEW label for study " .. studyId .. " is " .. age .. " seconds old")
        if age > 30 then
          print("Removing expired NEW label for study " .. studyId)
          local success, err = pcall(function() RestApiDelete("/studies/" .. studyId .. "/labels/NEW") end)
          if success then
            timestamps.NEW = nil
          else
            print("Failed to remove NEW label: " .. tostring(err))
          end
        end
      end
      if timestamps.MODIFIED then
        local age = currentTime - timestamps.MODIFIED
        print("MODIFIED label for study " .. studyId .. " is " .. age .. " seconds old")
        if age > 30 then
          print("Removing expired MODIFIED label for study " .. studyId)
          local success, err = pcall(function() RestApiDelete("/studies/" .. studyId .. "/labels/MODIFIED") end)
          if success then
            timestamps.MODIFIED = nil
          else
            print("Failed to remove MODIFIED label: " .. tostring(err))
          end
        end
      end
      if not timestamps.NEW and not timestamps.MODIFIED then
        activeLabels[studyId] = nil
        print("Cleared study " .. studyId .. " from activeLabels")
      end
    end
  end
  
  -- Handle uploads (triggered by new DICOM instances)
  function OnStoredInstance(instanceId, tags, metadata)
    local study = ParseJson(RestApiGet("/instances/" .. instanceId .. "/study"))
    local series = ParseJson(RestApiGet("/instances/" .. instanceId .. "/series"))
    local studyId = study.ID
    local currentTime = getCurrentTime()
    if not currentTime then
      print("Skipping label addition for study " .. studyId .. " due to time fetch failure")
      return
    end
  
    -- Add labels based on conditions
    local isFirstInstance = (#study.Series == 1 and #series.Instances == 1)
    if isFirstInstance and #study.Labels == 0 then
      print("Adding NEW label for study " .. studyId .. " at " .. currentTime)
      local success, err = pcall(function() RestApiPut("/studies/" .. studyId .. "/labels/NEW", '') end)
      if success then
        if not activeLabels[studyId] then activeLabels[studyId] = {} end
        activeLabels[studyId].NEW = currentTime
      else
        print("Failed to add NEW label: " .. tostring(err))
      end
    elseif not isFirstInstance then
      print("Adding MODIFIED label for study " .. studyId .. " at " .. currentTime)
      local success, err = pcall(function() RestApiPut("/studies/" .. studyId .. "/labels/MODIFIED", '') end)
      if success then
        if not activeLabels[studyId] then activeLabels[studyId] = {} end
        activeLabels[studyId].MODIFIED = currentTime
      else
        print("Failed to add MODIFIED label: " .. tostring(err))
      end
    end
  
    -- Run cleanup on every upload event
    cleanupExpiredLabels()
  end
  
  -- Handle modifications (triggered by study changes)
  function OnModifiedInstance(instanceId, tags, metadata, origin)
    local study = ParseJson(RestApiGet("/instances/" .. instanceId .. "/study"))
    local studyId = study.ID
    local currentTime = getCurrentTime()
    if not currentTime then
      print("Skipping label addition for study " .. studyId .. " due to time fetch failure")
      return
    end
  
    print("Adding MODIFIED label for study " .. studyId .. " at " .. currentTime)
    local success, err = pcall(function() RestApiPut("/studies/" .. studyId .. "/labels/MODIFIED", '') end)
    if success then
      if not activeLabels[studyId] then activeLabels[studyId] = {} end
      activeLabels[studyId].MODIFIED = currentTime
    else
      print("Failed to add MODIFIED label: " .. tostring(err))
    end
  
    -- Run cleanup on every modification event
    cleanupExpiredLabels()
  end
  
  -- Handle stable studies (runs when a study is fully received and stable)
  function OnStableStudy(studyId, tags, metadata)
    print("Study " .. studyId .. " stabilized")
    cleanupExpiredLabels()
  end
  
  -- Optional: Handle incoming HTTP requests (for debugging or manual triggers)
  function OnIncomingHttpRequest(method, uri, ip, username, httpHeaders)
    print("HTTP request received: " .. method .. " " .. uri .. " from " .. ip)
    cleanupExpiredLabels()
  end