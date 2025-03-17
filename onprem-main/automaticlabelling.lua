function makeValidLabel(input)
    return input:gsub("[^%w_-]", "-")
  end
  
  function OnStoredInstance(instanceId, tags, metadata)
    local study = ParseJson(RestApiGet("/instances/" .. instanceId .. "/study"))
    local series = ParseJson(RestApiGet("/instances/" .. instanceId .. "/series"))
    local isFirstInstance = (#study.Series == 1 and #series.Instances == 1)
  
    if isFirstInstance and #study.Labels == 0 then
      RestApiPut("/studies/" .. study.ID .. "/labels/NEW", '')
    elseif not isFirstInstance then
      RestApiPut("/studies/" .. study.ID .. "/labels/MODIFIED", '')
    end
  end
  
  function OnModifiedInstance(instanceId, tags, metadata, origin)
    local study = ParseJson(RestApiGet("/instances/" .. instanceId .. "/study"))
    if origin == "dicom-tag-modification" then
      RestApiPut("/studies/" .. study.ID .. "/labels/MODIFIED", '')
    end
  end
  
