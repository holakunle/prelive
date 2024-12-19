function sanitize(s)
   if s == nil then
       return nil
   end
   -- remove all characters that you don't want to have in a path
   s = string.gsub(s, " ", "-")
   s = string.gsub(s, "/", "-")
   s = string.gsub(s, "\\", "-")

   return s
end

-- adapt for windows/linux
-- don't forget trailing / or \\

 root = '/home/holyfire/test-storage-orthanc/'
sep =  '/'

-- root = 'C:\\Orthanc-organized-storage\\'
-- sep =  '\\'


function OnStoredInstance(instanceId, tags, metadata, origin)
   -- store files in a more human friendly hierarchy and then, delete the instance from Orthanc

   local institutionName = sanitize(tags["InstitutionName"])
   local patientId = sanitize(tags["PatientID"])
   local studyId = tags["StudyInstanceUID"]
   local seriesId = tags["SeriesInstanceUID"]
   local sopInstanceId = tags["SOPInstanceUID"]

   if (institutionName == nil or institutionName == "") then
        print("no InstitutionName, don't know what to do")
   else
      local dicom = RestApiGet('/instances/' .. instanceId .. '/file')
      local folder = root .. institutionName .. sep .. patientId .. sep .. studyId .. sep .. seriesId 
      print(folder)

      os.execute("mkdir -p " .. folder)
      local path = folder .. sep .. sopInstanceId .. ".dcm" 
      local file = io.open(path, "wb")
      io.output(file)
      io.write(dicom)
      io.close(file)

      Delete(instanceId) 
    end
end
