<#
.SYNOPSIS
Upload necessary files for Sitecore 9 and Habitat home Azure PaaS deployment

.DESCRIPTION
This script enables the upload of generated/downloaded WDP packages and accompanying Azure deployment files to an Azure storage account.
It then captures the URLs for each Azure upload and populates the azuredeploy.parameters.json and azureuser-config.json files

.PARAMETER ConfigurationFile
A cake-config.json file

#>

Param(
    [parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [String] $ConfigurationFile,
    [Switch] $SkipScUpload
)

###########################
# Find configuration files
###########################

Import-Module "$($PSScriptRoot)\ProcessConfigFile\ProcessConfigFile.psm1" -Force

$configarray = ProcessConfigFile -Config $ConfigurationFile
$config = $configarray[0]
$assetconfig = $configarray[1]
$azureuserconfig = $configarray[2]
$azureuserconfigfile = $configarray[4]
$topology = $configarray[5]

##########################
# Function for WDP uploads
##########################

Function CheckMd5{
    param(
        [string] $localFilePath,
        [string] $remoteBlobPath,
        $container,
        $context
    )
    $localMD5 = Get-FileHash -Path $localFilePath -Algorithm MD5
   
    try {
       $blob = Get-AzureStorageBlob -Blob $remoteBlobPath -Container $container -Context $context
       $cloudMD5 =  $blob.ICloudBlob.Properties.ContentMD5
    }
    catch{
        $cloudMd5 = $null
    }
    if ($cloudMd5 -ne $localMD5.Hash){
        return $false
    }
    else
    {
        return $true
    }
}
Function UploadWDPs ([PSCustomObject] $cakeJsonConfig, [PSCustomObject] $assetsJsonConfig, [Switch] $SkipScUpload) {

    $assetsFolder = (Join-Path $cakeJsonConfig.DeployFolder "assets")
    $sitecoreWDPpathArray = New-Object System.Collections.ArrayList
    $scUpload = $false
    $scUpload = ($assetsJsonConfig.prerequisites | Where-Object {$_.name -eq "Sitecore Experience Platform"} | Select-Object -first 1).uploadToAzure

    # Add Sitecore and habitat WDPs to upload list
    if ($cakeJsonConfig.Topology -eq "single") {
        if (!($SkipScUpload) -and ($ScUpload -eq $true)) {
            $sitecorepackages = Get-ChildItem -path $(Join-Path $([IO.Path]::Combine($assetsFolder, 'Sitecore Experience Platform')) *) -include *.zip -Exclude *xp1*, *cd*, *cm*, *prc*, *rep*
            $sitecoreWDPpathArray.AddRange($sitecorepackages)
        }

        $sitecoreWDPpathArray.Add($(Get-Item -Path $([IO.Path]::Combine($assetsFolder, 'habitathome', 'WDPWorkFolder', 'WDP', 'habitathome_single.scwdp.zip')))) | out-null
        $sitecoreWDPpathArray.Add($(Get-Item -Path $([IO.Path]::Combine($assetsFolder, 'xconnect', 'WDPWorkFolder', 'WDP', 'xconnect_single.scwdp.zip')))) | out-null
    }
    elseif ($cakeJsonConfig.Topology -eq "scaled") {
        if (!($SkipScUpload) -and ($ScUpload -eq $true)) {
            $sitecorepackages = Get-ChildItem -path $(Join-Path $([IO.Path]::Combine($assetsFolder, 'Sitecore Experience Platform')) *) -include *.zip -Exclude *xp0*, *single*
            $sitecoreWDPpathArray.AddRange($sitecorepackages) | out-null
        }
        
        $sitecoreWDPpathArray.Add($(Get-Item -Path $([IO.Path]::Combine($assetsFolder, 'habitathomeCD', 'WDPWorkFolder', 'WDP', 'habitathome_cd.scwdp.zip')))) | out-null
        $sitecoreWDPpathArray.Add($(Get-Item -Path $([IO.Path]::Combine($assetsFolder, 'habitathome', 'WDPWorkFolder', 'WDP', 'habitathome_single.scwdp.zip')))) | out-null   
        $sitecoreWDPpathArray.Add($(Get-Item -Path $([IO.Path]::Combine($assetsFolder, 'xconnect', 'WDPWorkFolder', 'WDP', 'xconnect_single.scwdp.zip')))) | out-null
    }

    if (!($SkipScUpload)) {
        # Add sitecore azure toolkit module bootloader 
        $sitecoreAsset = $assetsJsonConfig.prerequisites | Where-Object {$_.Name -eq "Sitecore Experience Platform"}
        if ($sitecoreAsset.FileName -match '([0-9]*\.[0-9]\.[0-9])') {
            $sepversion = $matches[0]
        }
        $sitecoreWDPpathArray.Add($(Get-Item -Path $([IO.Path]::Combine($cakeJsonConfig.DeployFolder, 'assets', 'Sitecore Azure Toolkit', 'resources', $sepversion, 'Addons', 'Sitecore.Cloud.Integration.Bootload.wdp.zip')))) | out-null
    }

    $assetsJsonConfig.prerequisites | Where-Object {
        $_.uploadToAzure -eq $true -and $_.isWdp -eq $true -and $_.install -eq $true} | ForEach-Object {
        $sitecoreWDPpathArray.Add((Get-ChildItem (Join-Path "C:\Deploy\assets" $_.name)))
    }
    $assetsJsonConfig.prerequisites | Where-Object {
        ($_.uploadToAzure -eq $true -and $_.isGroup -eq $true) -or ($_.convertToWdp -eq $true -and $_.install -eq $true)} | ForEach-Object {
        $sitecoreWDPpathArray.Add((Get-ChildItem (Join-Path "C:\Deploy\assets" $_.name)))
    }

    # Perform Upload
    foreach ($scwdpinarray in $sitecoreWDPpathArray) {
        if ($null -eq $scwdpinarray) {
            continue
        }
        Write-Host "Uploading '$($scwdpinarray.Name)'" -ForegroundColor Green
        if (!(CheckMD5 -localFilePath $scwdpinarray.FullName -remoteBlobPath "wdps/$($scwdpinarray.Name)" -container $containerName -context $ctx)){
            $md5 = Get-FileHash -Path $scwdpinarray.FullName -Algorithm MD5
        Set-AzureStorageBlobContent -File $scwdpinarray.FullName -Blob "wdps/$($scwdpinarray.Name)" -Container $containerName -Context $ctx -Force -Properties @{"ContentMD5" = $md5.Hash}
        Write-Host "Upload of '$($scwdpinarray.Name)' completed" -ForegroundColor Green
        }
        else {
            Write-Host "***  Skipping '$($scwdpinarray.Name)' - already exists" -ForegroundColor Green
        }
    }
}
                


###########################
# Function for file uploads
###########################

Function UploadFiles ([PSCustomObject] $cakeJsonConfig, [PSCustomObject] $assetsJsonConfig, [Switch] $SkipScUpload) {

    $sitecoreARMpathArray = New-Object System.Collections.ArrayList
    
    # Fetching all ARM templates' paths
    $sitecoreARMpathArray.Add($(Get-Item -Path $([IO.Path]::Combine($topology, 'ARM Templates', 'Habitat', 'habitathome.json')))) | out-null
    $sitecoreARMpathArray.Add($(Get-Item -Path $([IO.Path]::Combine($topology, 'ARM Templates', 'Habitat', 'xconnect.json')))) | out-null

    $defInstall = $assetsJsonConfig.prerequisites | Where-Object {$_.name -eq "Data Exchange Framework"} | % { $_.uploadToAzure -and $_.install}
    if ($defInstall) {
        $sitecoreARMpathArray.Add($(Get-Item -Path $([IO.Path]::Combine($topology, 'ARM Templates', 'Data Exchange Framework', 'def_module.json')))) | out-null
    }
    
    $sxaInstall = $assetsJsonConfig.prerequisites | Where-Object {$_.name -eq "Sitecore Experience Accelerator"} | % { $_.uploadToAzure -and $_.install}
    if ($sxaInstall) {
        $sitecoreARMpathArray.Add($(Get-Item -Path $([IO.Path]::Combine($topology, 'ARM Templates', 'Sitecore Experience Accelerator', 'sxa_module.json')))) | out-null
    }
    
    if (!($SkipScUpload)) {
  
        $sitecoreInstall = $assetsJsonConfig.prerequisites | Where-Object {$_.name -eq "Sitecore Experience Platform"} | % { $_.uploadToAzure -and $_.install}
        
        if ($sitecoreInstall) {
            $sitecoreARMpathArray.Add($(Get-Item -Path $([IO.Path]::Combine($topology, 'azuredeploy.json')))) | out-null
            $sitecoreARMpathArray.Add($(Get-Item -Path $([IO.Path]::Combine($topology, 'addons', 'bootloader.json')))) | out-null
        
            $nestedArmTemplates = Get-Item -Path $([IO.Path]::Combine($topology, 'nested'))
            
            Get-ChildItem -File -Path $nestedArmTemplates.FullName | ForEach-Object { 

                if (!(CheckMD5 -localFilePath $_.FullName -remoteBlobPath "arm-templates/$($nestedArmTemplates.Name)/$($_.Name)" -container $containerName -context $ctx)){
                    $md5 = Get-FileHash -Path $_.FullName -Algorithm MD5
                    Set-AzureStorageBlobContent -File $_.FullName -Blob "arm-templates/$($nestedArmTemplates.Name)/$($_.Name)" -Container $containerName -Context $ctx -Properties @{"ContentMD5" = $md5.Hash} -Force
                    Write-Host "Upload of '$($_.Name)' completed" -ForegroundColor Green
                }
                else {
                    Write-Host "***  Skipping '$($_.Name)' - already exists" -ForegroundColor Green
                }
            }
        }                 
    }

    # Checking if the files are already uploaded and present in Azure and uploading
    foreach ($scARMsInArray in $sitecoreARMpathArray) {      
        if (!(CheckMD5 -localFilePath $scARMsInArray.FullName -remoteBlobPath "arm-templates/$($scARMsInArray.Name)" -container $containerName -context $ctx))
        {
            Write-Host "Uploading $($scARMsInArray.Name)" -ForegroundColor Green
            $md5 = Get-FileHash -Path $scARMsInArray.FullName -Algorithm MD5
            Set-AzureStorageBlobContent -File $scARMsInArray.FullName -Blob "arm-templates/$($scARMsInArray.Name)" -Container $containerName -Context $ctx -Properties @{"ContentMD5" = $md5.Hash} -Force

            Write-Host "Upload of '$($_.Name)' completed" -ForegroundColor Green

        }    
        else{
            Write-Host "***  Skipping '$($_.Name)' - already exists" -ForegroundColor Green

        }   
    }
}

###################################################
# Upload created WDPs and additional files in Azure
###################################################

$azureDeploymentIdSetting = $azureuserconfig.settings | Where-Object {$_.id -eq "AzureDeploymentID"}
[string]$resourceGroupName = $azureDeploymentIdSetting.value 

$regionSetting = $azureuserconfig.settings | Where-Object {$_.id -eq "AzureRegion"}
$region = $regionSetting.value

$storageAccountSetting = $azureuserconfig.settings | Where-Object {$_.id -eq "StorageAccountName"}

if ([string]::IsNullOrEmpty($storageAccountSetting.value)) {

    # Generate a random name for the storage account by taking into account the 24 character limits imposed by Azure
    $seed = Get-Random -Maximum 99999
    $resourceGroupNameSeed = $resourceGroupName -replace '-', ''

    if ($resourceGroupNameSeed.length -gt 19) {
        $resourceGroupNameSeed = $resourceGroupNameSeed.substring(0, 19)
    }
    $storageAccountName = $resourceGroupNameSeed + $seed
}
else {
    $storageAccountName = $storageAccountSetting.value
}

$containerSetting = $azureuserconfig.settings | Where-Object {$_.id -eq "containerName"} 
if ([string]::IsNullOrEmpty($containerSetting.value)) {
    [String] $containerName = "hh-toolkit"
}
else {
    $containerName = $containerSetting.value
}

if (!($SkipScUpload)) {
    # Set variables for the container names
    [String] $additionalContainerName = "temp-hh-toolkit"

    # Trying to create a resource group for deployments to Azure, based on the selected region
    try {
        # Check if the resource group is already there
        Get-AzureRmResourceGroup -Name $resourceGroupName -ErrorAction Stop
        if ($null -ne (Get-AzureRmResourceGroup -Name $resourceGroupName)) {				
            Write-Host "A resource group named $($resourceGroupName) already exists" -ForegroundColor Yellow
        }
    } 
    catch {			
        # Create the resource group if the attempt to get the group fails
        Write-Host "Creating a new resource group named $($resourceGroupName)..." -ForegroundColor Green
        New-AzureRmResourceGroup -Name $resourceGroupName -Location $region		
    }
    try {
        $storageAccount = Get-AzureRmStorageAccount | Where-Object {$_.StorageAccountName -eq $storageAccountName}
        if ($null -eq $storageAccount) {
            # Try to create the storage account
            Write-Host "Creating a new storage account named $($storageAccountName)..." -ForegroundColor Green
            New-AzureRmStorageAccount -Name $storageAccountName -ResourceGroupName $resourceGroupName -Location $region -SkuName Standard_GRS -Kind BlobStorage -AccessTier Hot
        }
    } 
    catch {		
        # Create the storage account if one does not exist
        Write-Host "Creating a new storage account named $($storageAccountName)..."
        New-AzureRmStorageAccount -Name $storageAccountName -ResourceGroupName $resourceGroupName -Location $region -SkuName Standard_GRS -Kind BlobStorage -AccessTier Hot	
    }

    # Get the current storage account
    $sa = Get-AzureRmStorageAccount | Where-Object {$_.StorageAccountName -eq $storageAccountName } | Select-Object 

    # Obtain the storage account context
    $ctx = $sa.Context

    try {
        # Remove the temporary container if it exists
        "Trying to remove any temporary containers, created on previous runs of the script..."
        Remove-AzureStorageContainer -Name "$additionalContainerName" -Context $ctx -Force -ErrorAction Stop
    }
    catch {
        "...no temporary container found"
    }

    # Try to write to the container - if failing, use a temporary one
    try {
        "Verifying the existence of the current Azure container..."  
        # Check if the container name already exists and if it does, upload the WDP modules and additional files to the container
        Get-AzureStorageContainer -Container $containerName -Context $ctx -ErrorAction Stop
    } 
    catch {
        try {
            "Trying to create the container..."
            # Create the main container for the WDPs
            New-AzureStorageContainer -Name $containerName -Context $ctx -Permission off -ErrorAction Stop
        } 
        catch {
            "It seems like the container has been deleted very recently... creating a temporary container instead"
            $containerName = $additionalContainerName
            # Create a temporary container
            New-AzureStorageContainer -Name $containerName -Context $ctx -Permission off
        } 
    }

    # set the current values for container and storageaccount in the azureuser-config.json
    
    $containerSetting = $azureuserconfig.settings | Where-Object {$_.id -eq "containerName"}
    $containerSetting.value = $containerName

    $storageAccountSetting = $azureuserconfig.settings | Where-Object {$_.id -eq "storageAccountName"}
    $storageAccountSetting.value = $storageAccountName


    $azureuserconfig | ConvertTo-Json -Depth 5 | Set-Content $azureuserconfigfile

    UploadFiles -cakeJsonConfig $config -assetsJsonConfig $assetconfig
    UploadWDPs -cakeJsonConfig $config -assetsJsonConfig $assetconfig
}
else { #SkipSCUpload
    # Get the current storage account
    $sa = Get-AzureRmStorageAccount | Where-Object {$_.StorageAccountName -eq $storageAccountName } | Select-Object 

    # Obtain the storage account context
    $ctx = $sa.Context

    UploadFiles -cakeJsonConfig $config -assetsJsonConfig $assetconfig -SkipScUpload
    UploadWDPs -cakeJsonConfig $config -assetsJsonConfig $assetconfig -SkipScUpload
}


##############################################
# Get the URL for each WDP blob and record it
##############################################

$blobsList = Get-AzureStorageBlob -Container $containerName -Context $ctx
$assetsFolder = (Join-Path $config.DeployFolder "assets")
$defInstall = $false

$defAsset = $assetconfig.prerequisites | Where-Object {$_.Name -eq "Data Exchange Framework"}

if ($true -eq $defAsset.install) {
    $definstall = $true
    $defModule = $defAsset.modules | Where-Object {$_.Name -eq "Data Exchange Framework"}
    $defversion = $($defModule.FileName -replace '\.zip$', '')
    $defversion = $($defversion -replace '^Data Exchange Framework ', '')
}
$defCDAsset = $assetconfig.prerequisites | Where-Object {$_.Name -eq "Data Exchange Framework CD"}

if ($true -eq $defCDAsset.install) {
    $defCDModule = $defAsset.modules | Where-Object {$_.Name -eq "Data Exchange Framework CD"}
    $defCDversion = $($defCDModule.FileName -replace '\.zip$', '')
    $defCDversion = $($defCDversion -replace '^Data Exchange Framework CD Server ', '')

}

$sxaFileName = $assetconfig.prerequisites | Where-Object {$_.name -eq "Sitecore Experience Accelerator"} | Select -First 1 | Foreach-Object {$_.filename.ToString()}

$sxaBlob = $blobsList | Where-Object {($_.Name -replace "^wdps\/(.*)", '$1') -eq $sxaFileName}

if ($sxaBlob) {
    $sxaMsDeployPackageUrl = New-AzureStorageBlobSASToken -Container $containerName `
        -Blob $sxaBlob.Name `
        -Permission rwd `
        -StartTime (Get-Date) `
        -ExpiryTime (Get-Date).AddDays(3650) `
        -Context $ctx `
        -FullUri
}

$speFileName = ($assetconfig.prerequisites | Where-Object {$_.name -eq "Sitecore PowerShell Extensions"}).filename.ToString()
$speBlob = $blobsList | Where-Object {($_.Name -replace "^wdps\/(.*)", '$1') -eq $speFileName}

if ($speBlob) {
    $speMsDeployPackageUrl = New-AzureStorageBlobSASToken -Container $containerName `
        -Blob $speBlob.Name `
        -Permission rwd `
        -StartTime (Get-Date) `
        -ExpiryTime (Get-Date).AddDays(3650) `
        -Context $ctx `
        -FullUri
}

$msDeployPackageUrl = $blobsList | Where-Object {
    $_.name -eq "wdps/Sitecore.Cloud.Integration.Bootload.wdp.zip"} | Select -First 1 | ForEach-Object {
    New-AzureStorageBlobSASToken -Container $containerName `
        -Blob $_.Name `
        -Permission rwd `
        -StartTime (Get-Date) `
        -ExpiryTime (Get-Date).AddDays(3650) `
        -Context $ctx `
        -FullUri
}
$habitatWebsiteDeployPackageUrl = $blobsList | Where-Object {
    $_.name -eq "wdps/habitathome_single.scwdp.zip"} | Select -First 1 | ForEach-Object {
    New-AzureStorageBlobSASToken -Container $containerName `
        -Blob $_.Name `
        -Permission rwd `
        -StartTime (Get-Date) `
        -ExpiryTime (Get-Date).AddDays(3650) `
        -Context $ctx `
        -FullUri
}
$habitatXconnectDeployPackageUrl = $blobsList | Where-Object {
    $_.name -eq "wdps/xconnect_single.scwdp.zip"} | Select -First 1 | ForEach-Object {
    New-AzureStorageBlobSASToken -Container $containerName `
        -Blob $_.Name `
        -Permission rwd `
        -StartTime (Get-Date) `
        -ExpiryTime (Get-Date).AddDays(3650) `
        -Context $ctx `
        -FullUri
}

if ($definstall -eq $true) {
    $defDeployPackageUrl = $blobsList | Where-Object {
        $_.name -eq "wdps/Data Exchange Framework " + $defversion + "_single.scwdp.zip"} | Select -First 1 | ForEach-Object {
        New-AzureStorageBlobSASToken -Container $containerName `
            -Blob $_.Name `
            -Permission rwd `
            -StartTime (Get-Date) `
            -ExpiryTime (Get-Date).AddDays(3650) `
            -Context $ctx `
            -FullUri
    }
    $defSitecoreDeployPackageUrl = $blobsList | Where-Object {
        $_.name -eq "wdps/Sitecore Provider for Data Exchange Framework " + $defversion + "_single.scwdp.zip"} | Select -First 1 | ForEach-Object {
        New-AzureStorageBlobSASToken -Container $containerName `
            -Blob $_.Name `
            -Permission rwd `
            -StartTime (Get-Date) `
            -ExpiryTime (Get-Date).AddDays(3650) `
            -Context $ctx `
            -FullUri
    }
    $defSqlDeployPackageUrl = $blobsList | Where-Object {
        $_.name -eq "wdps/SQL Provider for Data Exchange Framework " + $defversion + "_single.scwdp.zip"} | Select -First 1 | ForEach-Object {
        New-AzureStorageBlobSASToken -Container $containerName `
            -Blob $_.Name `
            -Permission rwd `
            -StartTime (Get-Date) `
            -ExpiryTime (Get-Date).AddDays(3650) `
            -Context $ctx `
            -FullUri
    }
    $defxConnectDeployPackageUrl = $blobsList | Where-Object {
        $_.name -eq "wdps/xConnect Provider for Data Exchange Framework " + $defversion + "_single.scwdp.zip"} | Select -First 1 | ForEach-Object {
        New-AzureStorageBlobSASToken -Container $containerName `
            -Blob $_.Name `
            -Permission rwd `
            -StartTime (Get-Date) `
            -ExpiryTime (Get-Date).AddDays(3650) `
            -Context $ctx `
            -FullUri
    }
    $defDynamicsDeployPackageUrl = $blobsList | Where-Object {
        $_.name -eq "wdps/Dynamics Provider for Data Exchange Framework " + $defversion + "_single.scwdp.zip"} | Select -First 1 | ForEach-Object {
        New-AzureStorageBlobSASToken -Container $containerName `
            -Blob $_.Name `
            -Permission rwd `
            -StartTime (Get-Date) `
            -ExpiryTime (Get-Date).AddDays(3650) `
            -Context $ctx `
            -FullUri
    }
    $defDynamicsConnectDeployPackageUrl = $blobsList | Where-Object {
        $_.name -eq "wdps/Connect for Microsoft Dynamics " + $defversion + "_single.scwdp.zip"} | Select -First 1 | ForEach-Object {
        New-AzureStorageBlobSASToken -Container $containerName `
            -Blob $_.Name `
            -Permission rwd `
            -StartTime (Get-Date) `
            -ExpiryTime (Get-Date).AddDays(3650) `
            -Context $ctx `
            -FullUri
    }

    $defSalesforceDeployPackageUrl = $blobsList | Where-Object {
        $_.name -eq "wdps/Salesforce Provider for Data Exchange Framework " + $defversion + "_single.scwdp.zip"} | Select -First 1 | ForEach-Object {
        New-AzureStorageBlobSASToken -Container $containerName `
            -Blob $_.Name `
            -Permission rwd `
            -StartTime (Get-Date) `
            -ExpiryTime (Get-Date).AddDays(3650) `
            -Context $ctx `
            -FullUri
    }
    $defSalesforceConnectDeployPackageUrl = $blobsList | Where-Object {
        $_.name -eq "wdps/Connect for Salesforce " + $defversion + "_single.scwdp.zip"} | Select -First 1 | ForEach-Object {
        New-AzureStorageBlobSASToken -Container $containerName `
            -Blob $_.Name `
            -Permission rwd `
            -StartTime (Get-Date) `
            -ExpiryTime (Get-Date).AddDays(3650) `
            -Context $ctx `
            -FullUri
    }
}


if ($config.Topology -eq "single") {

    $localSitecoreassets = Get-ChildItem -path $(Join-Path $assetsfolder "Sitecore Experience Platform\*") -include *.zip -Exclude *xp1*, *cd*, *cm*, *prc*, *rep*

    $localSCfile = $localSitecoreassets | Where-Object {$_.name -like "*_single.scwdp.zip"}

    $singleMsDeployPackageUrl = $blobsList | Where-Object {($_.Name -replace "^wdps\/(.*)", '$1') -eq $localScFile.Name} | Select -First 1 | ForEach-Object {
        New-AzureStorageBlobSASToken -Container $containerName `
            -Blob $_.Name `
            -Permission rwd `
            -StartTime (Get-Date) `
            -ExpiryTime (Get-Date).AddDays(3650) `
            -Context $ctx `
            -FullUri
    }
    $localXCFile = $localSitecoreassets | Where-Object {$_.name -like "*_xp0xconnect.scwdp.zip"}
    $xcSingleMsDeployPackageUrl = $blobsList | Where-Object {($_.Name -replace "^wdps\/(.*)", '$1') -eq $localXCFile.Name} | Select -First 1 | ForEach-Object {
        New-AzureStorageBlobSASToken -Container $containerName `
            -Blob $_.Name `
            -Permission rwd `
            -StartTime (Get-Date) `
            -ExpiryTime (Get-Date).AddDays(3650) `
            -Context $ctx `
            -FullUri
    }
}
elseif ($config.Topology -eq "scaled") {

    $localSitecoreassets = Get-ChildItem -path $(Join-Path $assetsfolder "Sitecore Experience Platform\*") -include *.zip -Exclude *xp0*, *single*
    ### See TODO above - should be able to directly search against blobsList rather than loop
    
    $cmFile = $localSitecoreassets | Where-Object {$_.name -like "*_cm.scwdp.zip" }
    $cmMsDeployPackageUrl = $blobsList | Where-Object {($_.Name -replace "^wdps\/(.*)", '$1') -eq $cmFile.Name} | Select -First 1 | ForEach-Object {
        New-AzureStorageBlobSASToken -Container $containerName `
            -Blob $_.Name `
            -Permission rwd `
            -StartTime (Get-Date) `
            -ExpiryTime (Get-Date).AddDays(3650) `
            -Context $ctx `
            -FullUri
    }

    $cdFile = $localSitecoreassets | Where-Object {$_.name -like "*_cd.scwdp.zip" }
    $cdMsDeployPackageUrl = $blobsList | Where-Object {($_.Name -replace "^wdps\/(.*)", '$1') -eq $cdFile.Name} | Select -First 1 | ForEach-Object {
        New-AzureStorageBlobSASToken -Container $containerName `
            -Blob $_.Name `
            -Permission rwd `
            -StartTime (Get-Date) `
            -ExpiryTime (Get-Date).AddDays(3650) `
            -Context $ctx `
            -FullUri
    }
    $prcFile = $localSitecoreassets | Where-Object {$_.name -like "*_prc.scwdp.zip" }
    $prcMsDeployPackageUrl = $blobsList | Where-Object {($_.Name -replace "^wdps\/(.*)", '$1') -eq $prcFile.Name} | Select -First 1 | ForEach-Object {
        New-AzureStorageBlobSASToken -Container $containerName `
            -Blob $_.Name `
            -Permission rwd `
            -StartTime (Get-Date) `
            -ExpiryTime (Get-Date).AddDays(3650) `
            -Context $ctx `
            -FullUri
    }
    $repFile = $localSitecoreassets | Where-Object {$_.name -like "*_rep.scwdp.zip" }
    $repMsDeployPackageUrl = $blobsList | Where-Object {($_.Name -replace "^wdps\/(.*)", '$1') -eq $repFile.Name} | Select -First 1 | ForEach-Object {
        New-AzureStorageBlobSASToken -Container $containerName `
            -Blob $_.Name `
            -Permission rwd `
            -StartTime (Get-Date) `
            -ExpiryTime (Get-Date).AddDays(3650) `
            -Context $ctx `
            -FullUri
    }             
    $xcRefFile = $localSitecoreassets | Where-Object {$_.name -like "*_xp1referencedata.scwdp.zip" }
    $xcRefDataMsDeployPackageUrl = $blobsList | Where-Object {($_.Name -replace "^wdps\/(.*)", '$1') -eq $xcRefFile.Name} | Select -First 1 | ForEach-Object {
        New-AzureStorageBlobSASToken -Container $containerName `
            -Blob $_.Name `
            -Permission rwd `
            -StartTime (Get-Date) `
            -ExpiryTime (Get-Date).AddDays(3650) `
            -Context $ctx `
            -FullUri
    }       
    $xcCollectFile = $localSitecoreassets | Where-Object {$_.name -like "*_xp1collection.scwdp.zip" }
    $xcCollectMsDeployPackageUrl = $blobsList | Where-Object {($_.Name -replace "^wdps\/(.*)", '$1') -eq $xcCollectFile.Name} | Select -First 1 | ForEach-Object {
        New-AzureStorageBlobSASToken -Container $containerName `
            -Blob $_.Name `
            -Permission rwd `
            -StartTime (Get-Date) `
            -ExpiryTime (Get-Date).AddDays(3650) `
            -Context $ctx `
            -FullUri
    }  
    $xcSearchFile = $localSitecoreassets | Where-Object {$_.name -like "*_xp1collectionsearch.scwdp.zip" }
    $xcSearchMsDeployPackageUrl = $blobsList | Where-Object {($_.Name -replace "^wdps\/(.*)", '$1') -eq $xcSearchFile.Name} | Select -First 1 | ForEach-Object {
        New-AzureStorageBlobSASToken -Container $containerName `
            -Blob $_.Name `
            -Permission rwd `
            -StartTime (Get-Date) `
            -ExpiryTime (Get-Date).AddDays(3650) `
            -Context $ctx `
            -FullUri
    }               
    $maOpsFile = $localSitecoreassets | Where-Object {$_.name -like "*_xp1marketingautomation.scwdp.zip" }
    $maOpsMsDeployPackageUrl = $blobsList | Where-Object {($_.Name -replace "^wdps\/(.*)", '$1') -eq $maOpsFile.Name} | Select -First 1 | ForEach-Object {
        New-AzureStorageBlobSASToken -Container $containerName `
            -Blob $_.Name `
            -Permission rwd `
            -StartTime (Get-Date) `
            -ExpiryTime (Get-Date).AddDays(3650) `
            -Context $ctx `
            -FullUri
    }      
    $maRepFile = $localSitecoreassets | Where-Object {$_.name -like "*_xp1marketingautomationreporting.scwdp.zip" }
    $maRepMsDeployPackageUrl = $blobsList | Where-Object {($_.Name -replace "^wdps\/(.*)", '$1') -eq $maRepFile.Name} | Select -First 1 | ForEach-Object {
        New-AzureStorageBlobSASToken -Container $containerName `
            -Blob $_.Name `
            -Permission rwd `
            -StartTime (Get-Date) `
            -ExpiryTime (Get-Date).AddDays(3650) `
            -Context $ctx `
            -FullUri
    }                
                    
    $sxaCDFile = $assetconfig.prerequisites | Where-Object {$_.Name -eq "Sitecore Experience Accelerator CD"}
    $sxaCDMsDeployPackageUrl = $blobsList | Where-Object {($_.Name -replace "^wdps\/(.*)", '$1') -eq $sxaCDFile.FileName} | Select -First 1 | ForEach-Object {
        New-AzureStorageBlobSASToken -Container $containerName `
            -Blob $_.Name `
            -Permission rwd `
            -StartTime (Get-Date) `
            -ExpiryTime (Get-Date).AddDays(3650) `
            -Context $ctx `
            -FullUri
    }      
   
   
    $habitatWebsiteCDdeployPackageUrl = $blobsList | Where-Object {
        $_.name -eq "wdps/habitathome_cd.scwdp.zip"} | Select -First 1 | ForEach-Object {
        New-AzureStorageBlobSASToken -Container $containerName `
            -Blob $_.Name `
            -Permission rwd `
            -StartTime (Get-Date) `
            -ExpiryTime (Get-Date).AddDays(3650) `
            -Context $ctx `
            -FullUri
    }   



    if ($definstall -eq $true) {
        $defCDDeployPackageUrl = $blobsList | Where-Object {
            $_.name -eq "wdps/Data Exchange Framework CD Server " + $defCDversion + "_scaled.scwdp.zip"} | Select -First 1 | ForEach-Object {
            New-AzureStorageBlobSASToken -Container $containerName `
                -Blob $_.Name `
                -Permission rwd `
                -StartTime (Get-Date) `
                -ExpiryTime (Get-Date).AddDays(3650) `
                -Context $ctx `
                -FullUri
        }
        $defSitecoreCDDeployPackageUrl = $blobsList | Where-Object {
            $_.name -eq "wdps/Sitecore Provider for Data Exchange Framework CD Server " + $defCDversion + "_scaled.scwdp.zip"} | Select -First 1 | ForEach-Object {
            New-AzureStorageBlobSASToken -Container $containerName `
                -Blob $_.Name `
                -Permission rwd `
                -StartTime (Get-Date) `
                -ExpiryTime (Get-Date).AddDays(3650) `
                -Context $ctx `
                -FullUri
        }
        $defSqlCDDeployPackageUrl = $blobsList | Where-Object {
            $_.name -eq "wdps/SQL Provider for Data Exchange Framework CD Server " + $defCDversion + "_scaled.scwdp.zip"} | Select -First 1 | ForEach-Object {
            New-AzureStorageBlobSASToken -Container $containerName `
                -Blob $_.Name `
                -Permission rwd `
                -StartTime (Get-Date) `
                -ExpiryTime (Get-Date).AddDays(3650) `
                -Context $ctx `
                -FullUri
        }
        $defxConnectCDDeployPackageUrl = $blobsList | Where-Object {
            $_.name -eq "wdps/xConnect Provider for Data Exchange Framework CD Server " + $defCDversion + "_scaled.scwdp.zip"} | Select -First 1 | ForEach-Object {
            New-AzureStorageBlobSASToken -Container $containerName `
                -Blob $_.Name `
                -Permission rwd `
                -StartTime (Get-Date) `
                -ExpiryTime (Get-Date).AddDays(3650) `
                -Context $ctx `
                -FullUri
        }
        $defDynamicsCDDeployPackageUrl = $blobsList | Where-Object {
            $_.name -eq "wdps/Dynamics Provider for Data Exchange Framework CD Server " + $defCDversion + "_scaled.scwdp.zip"} | Select -First 1 | ForEach-Object {
            New-AzureStorageBlobSASToken -Container $containerName `
                -Blob $_.Name `
                -Permission rwd `
                -StartTime (Get-Date) `
                -ExpiryTime (Get-Date).AddDays(3650) `
                -Context $ctx `
                -FullUri
        }
        $defDynamicsConnectCDDeployPackageUrl = $blobsList | Where-Object {
            $_.name -eq "wdps/Connect for Microsoft Dynamics CD Server " + $defCDversion + "_scaled.scwdp.zip"} | Select -First 1 | ForEach-Object {
            New-AzureStorageBlobSASToken -Container $containerName `
                -Blob $_.Name `
                -Permission rwd `
                -StartTime (Get-Date) `
                -ExpiryTime (Get-Date).AddDays(3650) `
                -Context $ctx `
                -FullUri
        }

        $defSalesforceCDDeployPackageUrl = $blobsList | Where-Object {
            $_.name -eq "wdps/Salesforce Provider for Data Exchange Framework CD Server " + $defCDversion + "_scaled.scwdp.zip"} | Select -First 1 | ForEach-Object {
            New-AzureStorageBlobSASToken -Container $containerName `
                -Blob $_.Name `
                -Permission rwd `
                -StartTime (Get-Date) `
                -ExpiryTime (Get-Date).AddDays(3650) `
                -Context $ctx `
                -FullUri
        }
        $defSalesforceConnectCDDeployPackageUrl = $blobsList | Where-Object {
            $_.name -eq "wdps/Connect for Salesforce CD Server " + $defCDversion + "_scaled.scwdp.zip"} | Select -First 1 | ForEach-Object {
            New-AzureStorageBlobSASToken -Container $containerName `
                -Blob $_.Name `
                -Permission rwd `
                -StartTime (Get-Date) `
                -ExpiryTime (Get-Date).AddDays(3650) `
                -Context $ctx `
                -FullUri
        }
    }
}



#############################################################
# Get the URL of each required additional file and record it
#############################################################
$sxaTemplateLink = $blobsList | Where-Object {$_.Name -like "*sxa*.json"} | Select -First 1 | ForEach-Object {
    New-AzureStorageBlobSASToken -Container $containerName `
        -Blob $_.Name `
        -Permission rwd `
        -StartTime (Get-Date) `
        -ExpiryTime (Get-Date).AddDays(3650) `
        -Context $ctx `
        -FullUri

}
$defTemplateLink = $blobsList | Where-Object {$_.Name -like "*def*.json"}|  Select -First 1 | ForEach-Object {
    New-AzureStorageBlobSASToken -Container $containerName `
        -Blob $_.Name `
        -Permission rwd `
        -StartTime (Get-Date) `
        -ExpiryTime (Get-Date).AddDays(3650) `
        -Context $ctx `
        -FullUri

}
$habitatWebsiteTemplateLink = $blobsList | Where-Object {$_.Name -like "*habitathome.json"}|  Select -First 1 | ForEach-Object {
    New-AzureStorageBlobSASToken -Container $containerName `
        -Blob $_.Name `
        -Permission rwd `
        -StartTime (Get-Date) `
        -ExpiryTime (Get-Date).AddDays(3650) `
        -Context $ctx `
        -FullUri

}
$habitatXconnectTemplateLink = $blobsList | Where-Object {$_.Name -like "*xconnect.json"}|  Select -First 1 | ForEach-Object {
    New-AzureStorageBlobSASToken -Container $containerName `
        -Blob $_.Name `
        -Permission rwd `
        -StartTime (Get-Date) `
        -ExpiryTime (Get-Date).AddDays(3650) `
        -Context $ctx `
        -FullUri

}
$bootloaderTemplateLink = $blobsList | Where-Object {$_.Name -like "*bootloader.json"} | Select -First 1 | ForEach-Object {
    New-AzureStorageBlobSASToken -Container $containerName `
        -Blob $_.Name `
        -Permission rwd `
        -StartTime (Get-Date) `
        -ExpiryTime (Get-Date).AddDays(3650) `
        -Context $ctx `
        -FullUri
}
  



########################################
# Construct azuredeploy.parameters.json
########################################

# Find and process the azuredeploy.parameters.json template

[String] $azuredeployConfigFile = $null

if ($definstall -eq $true) {
    $azuredeployConfigFile = $([IO.Path]::Combine($topology, 'azuredeploy.parameters.json'))
}
else {
    $azuredeployConfigFile = $([IO.Path]::Combine($topology, 'azuredeploy.parametersWOdef.json'))
}

if (!(Test-Path $azuredeployConfigFile)) {
    Write-Host "Azuredeploy parameters file '$($azuredeployConfigFile)' not found." -ForegroundColor Red
    Write-Host "Please ensure there is an azuredeploy.parameters.json file at '$($azuredeployConfigFile)'" -ForegroundColor Red
    Exit 1
}

$azuredeployConfig = Get-Content -Raw $azuredeployConfigFile |  ConvertFrom-Json
if (!$azuredeployConfig) {
    throw "Error trying to load the Azuredeploy parameters file!"
}

# Get all user-defined settings from the azureuser-config.json files and assign them to variables

$deploymentId = ($azureuserconfig.settings | Where-Object {$_.id -eq "AzureDeploymentID"}).value
$location = ($azureuserconfig.settings | Where-Object {$_.id -eq "AzureRegion"}).value
$authCertificateFilePath = ($azureuserconfig.settings | Where-Object {$_.id -eq "XConnectCertFilePath"}).value
$authCertificatePassword = ($azureuserconfig.settings | Where-Object {$_.id -eq "XConnectCertificatePassword"}).value
$sitecoreAdminPassword = ($azureuserconfig.settings | Where-Object {$_.id -eq "SitecoreLoginAdminPassword"}).value
$licenseXml = ($azureuserconfig.settings | Where-Object {$_.id -eq "SitecoreLicenseXMLPath"}).value
$sqlServerLogin = ($azureuserconfig.settings | Where-Object {$_.id -eq "SqlServerLoginAdminAccount"}).value
$sqlServerPassword = ($azureuserconfig.settings | Where-Object {$_.id -eq "SqlServerLoginAdminPassword"}).value
$ArmTemplateUrl = ($azureuserconfig.settings | Where-Object {$_.id -eq "ArmTemplateUrl"}).value
$templatelinkAccessToken = ($azureuserconfig.settings | Where-Object {$_.id -eq "templatelinkAccessToken"}).value

# Set ArmTemplateURl and templateLinkAccessToken if blank
if ([string]::IsNullOrEmpty($templatelinkAccessToken) -or [string]::IsNullOrEmpty($ArmTemplateUrl)) {
    if ([string]::IsNullOrEmpty($ArmTemplateUrl)) {
        $ArmTemplateUrl = New-AzureStorageBlobSASToken -Container $containerName `
            -Blob 'arm-templates/azuredeploy.json' `
            -Permission rwd `
            -StartTime (Get-Date) `
            -ExpiryTime (Get-Date).AddDays(3650) `
            -Context $ctx `
            -FullUri
    }

    if ([string]::IsNullOrEmpty($templatelinkAccessToken)) {
        $templatelinkAccessToken = New-AzureStorageContainerSASToken $containerName `
            -Permission rwd `
            -StartTime (Get-Date) `
            -ExpiryTime (Get-Date).AddDays(3650) `
            -Context $ctx
    }
    
    
    ($azureuserconfig.settings | Where-Object {$_.id -eq "ArmTemplateUrl"}).value = $ArmTemplateUrl
    ($azureuserconfig.settings | Where-Object {$_.id -eq "templatelinkAccessToken"}).value = $templatelinkAccessToken
    

    $azureuserconfig | ConvertTo-Json -Depth 5 | Set-Content $azureuserconfigfile
}

# Populate parameters inside the azuredeploy.parameters JSON schema with values from previously prepared variables
if ($definstall -eq $true) {
    if ($config.Topology -eq "single") {
        $azuredeployConfig.parameters | ForEach-Object {
            $_.deploymentId.value = $deploymentId
            $_.location.value = $location
            $_.sitecoreAdminPassword.value = $sitecoreAdminPassword
            $_.licenseXml.value = $licenseXml
            $_.sqlServerLogin.value = $sqlServerLogin
            $_.sqlServerPassword.value = $sqlServerPassword
            $_.authCertificatePassword.value = $authCertificatePassword
            $_.singleMsDeployPackageUrl.value = $singleMsDeployPackageUrl
            $_.xcSingleMsDeployPackageUrl.value = $xcSingleMsDeployPackageUrl
            $_.modules.value.items[0].parameters.sxaMsDeployPackageUrl = $sxaMsDeployPackageUrl
            $_.modules.value.items[0].parameters.speMsDeployPackageUrl = $speMsDeployPackageUrl
            $_.modules.value.items[0].templateLink = $sxaTemplateLink
            $_.modules.value.items[1].parameters.defDeployPackageUrl = $defDeployPackageUrl
            $_.modules.value.items[1].parameters.defSitecoreDeployPackageUrl = $defSitecoreDeployPackageUrl
            $_.modules.value.items[1].parameters.defSqlDeployPackageUrl = $defSqlDeployPackageUrl
            $_.modules.value.items[1].parameters.defxConnectDeployPackageUrl = $defxConnectDeployPackageUrl
            $_.modules.value.items[1].parameters.defDynamicsDeployPackageUrl = $defDynamicsDeployPackageUrl
            $_.modules.value.items[1].parameters.defDynamicsConnectDeployPackageUrl = $defDynamicsConnectDeployPackageUrl
            $_.modules.value.items[1].parameters.defSalesforceDeployPackageUrl = $defSalesforceDeployPackageUrl
            $_.modules.value.items[1].parameters.defSalesforceConnectDeployPackageUrl = $defSalesforceConnectDeployPackageUrl
            $_.modules.value.items[1].templateLink = $defTemplateLink
            $_.modules.value.items[2].parameters.habitatWebsiteDeployPackageUrl = $habitatWebsiteDeployPackageUrl
            $_.modules.value.items[2].templateLink = $habitatWebsiteTemplateLink
            $_.modules.value.items[3].parameters.habitatXconnectDeployPackageUrl = $habitatXconnectDeployPackageUrl
            $_.modules.value.items[3].templateLink = $habitatXconnectTemplateLink
            $_.modules.value.items[4].parameters.msDeployPackageUrl = $msDeployPackageUrl
            $_.modules.value.items[4].templateLink = $bootloaderTemplateLink
        }
    }
    else {
        # Topology -eq "scaled"
        $azuredeployConfig.parameters | ForEach-Object {
            $_.deploymentId.value = $deploymentId
            $_.location.value = $location
            $_.sitecoreAdminPassword.value = $sitecoreAdminPassword
            $_.licenseXml.value = $licenseXml
            $_.repAuthenticationApiKey.value = $(New-Guid)
            $_.sqlServerLogin.value = $sqlServerLogin
            $_.sqlServerPassword.value = $sqlServerPassword
            $_.authCertificatePassword.value = $authCertificatePassword
            $_.cmMsDeployPackageUrl.value = $cmMsDeployPackageUrl
            $_.cdMsDeployPackageUrl.value = $cdMsDeployPackageUrl
            $_.cdMsDeployPackageUrl.value = $cdMsDeployPackageUrl
            $_.prcMsDeployPackageUrl.value = $prcMsDeployPackageUrl
            $_.repMsDeployPackageUrl.value = $repMsDeployPackageUrl
            $_.xcRefDataMsDeployPackageUrl.value = $xcRefDataMsDeployPackageUrl
            $_.xcCollectMsDeployPackageUrl.value = $xcCollectMsDeployPackageUrl
            $_.xcSearchMsDeployPackageUrl.value = $xcSearchMsDeployPackageUrl
            $_.maOpsMsDeployPackageUrl.value = $maOpsMsDeployPackageUrl
            $_.maRepMsDeployPackageUrl.value = $maRepMsDeployPackageUrl
            $_.modules.value.items[0].parameters.cdSxaMsDeployPackageUrl = $sxaCDMsDeployPackageUrl
            $_.modules.value.items[0].parameters.cmSxaMsDeployPackageUrl = $sxaMsDeployPackageUrl
            $_.modules.value.items[0].parameters.speMsDeployPackageUrl = $speMsDeployPackageUrl
            $_.modules.value.items[0].templateLink = $sxaTemplateLink
            $_.modules.value.items[1].parameters.defDeployPackageUrl = $defDeployPackageUrl
            $_.modules.value.items[1].parameters.defSitecoreDeployPackageUrl = $defSitecoreDeployPackageUrl
            $_.modules.value.items[1].parameters.defSqlDeployPackageUrl = $defSqlDeployPackageUrl
            $_.modules.value.items[1].parameters.defxConnectDeployPackageUrl = $defxConnectDeployPackageUrl
            $_.modules.value.items[1].parameters.defDynamicsDeployPackageUrl = $defDynamicsDeployPackageUrl
            $_.modules.value.items[1].parameters.defDynamicsConnectDeployPackageUrl = $defDynamicsConnectDeployPackageUrl
            $_.modules.value.items[1].parameters.defSalesforceDeployPackageUrl = $defSalesforceDeployPackageUrl
            $_.modules.value.items[1].parameters.defSalesforceConnectDeployPackageUrl = $defSalesforceConnectDeployPackageUrl
            $_.modules.value.items[1].parameters.defCdDeployPackageUrl = $defCDdeployPackageUrl
            $_.modules.value.items[1].parameters.defSitecoreCdDeployPackageUrl = $defSitecoreCDdeployPackageUrl
            $_.modules.value.items[1].parameters.defSqlCdDeployPackageUrl = $defSqlCDdeployPackageUrl
            $_.modules.value.items[1].parameters.defxConnectCdDeployPackageUrl = $defxConnectCDdeployPackageUrl
            $_.modules.value.items[1].parameters.defDynamicsCdDeployPackageUrl = $defDynamicsCDdeployPackageUrl
            $_.modules.value.items[1].parameters.defDynamicsConnectCdDeployPackageUrl = $defDynamicsConnectCDdeployPackageUrl
            $_.modules.value.items[1].parameters.defSalesforceCdDeployPackageUrl = $defSalesforceCDdeployPackageUrl
            $_.modules.value.items[1].parameters.defSalesforceConnectCdDeployPackageUrl = $defSalesforceConnectCDdeployPackageUrl
            $_.modules.value.items[1].templateLink = $defTemplateLink
            $_.modules.value.items[2].parameters.habitatWebsiteCdMsDeployPackageUrl = $habitatWebsiteCDdeployPackageUrl
            $_.modules.value.items[2].parameters.habitatWebsiteCmMsDeployPackageUrl = $habitatWebsiteDeployPackageUrl
            $_.modules.value.items[2].templateLink = $habitatWebsiteTemplateLink
            $_.modules.value.items[3].parameters.habitatXconnectDeployPackageUrl = $habitatXconnectDeployPackageUrl
            $_.modules.value.items[3].templateLink = $habitatXconnectTemplateLink
            $_.modules.value.items[4].parameters.msDeployPackageUrl = $msDeployPackageUrl
            $_.modules.value.items[4].templateLink = $bootloaderTemplateLink
        }
    }
}
else {
    # $definstall -eq $false
    if ($config.Topology -eq "single") {
        $params = $azuredeployConfig.parameters 
        $params.deploymentId.value = $deploymentId
        $params.location.value = $location
        $params.sitecoreAdminPassword.value = $sitecoreAdminPassword
        $params.licenseXml.value = $licenseXml
        $params.sqlServerLogin.value = $sqlServerLogin
        $params.sqlServerPassword.value = $sqlServerPassword
        $params.authCertificatePassword.value = $authCertificatePassword
        $params.singleMsDeployPackageUrl.value = $singleMsDeployPackageUrl
        $params.xcSingleMsDeployPackageUrl.value = $xcSingleMsDeployPackageUrl
        $params.modules.value.items[0].parameters.sxaMsDeployPackageUrl = $sxaMsDeployPackageUrl
        $params.modules.value.items[0].parameters.speMsDeployPackageUrl = $speMsDeployPackageUrl
        $params.modules.value.items[0].templateLink = $sxaTemplateLink
        $params.modules.value.items[1].parameters.habitatWebsiteDeployPackageUrl = $habitatWebsiteDeployPackageUrl
        $params.modules.value.items[1].templateLink = $habitatWebsiteTemplateLink
        $params.modules.value.items[2].parameters.habitatXconnectDeployPackageUrl = $habitatXconnectDeployPackageUrl
        $params.modules.value.items[2].templateLink = $habitatXconnectTemplateLink
        $params.modules.value.items[3].parameters.msDeployPackageUrl = $msDeployPackageUrl
        $params.modules.value.items[3].templateLink = $bootloaderTemplateLink
        
    }
    else {
        # topology -eq scaled
        $azuredeployConfig.parameters | ForEach-Object {
            $_.deploymentId.value = $deploymentId
            $_.location.value = $location
            $_.sitecoreAdminPassword.value = $sitecoreAdminPassword
            $_.licenseXml.value = $licenseXml
            $_.repAuthenticationApiKey.value = $(New-Guid)
            $_.sqlServerLogin.value = $sqlServerLogin
            $_.sqlServerPassword.value = $sqlServerPassword
            $_.authCertificatePassword.value = $authCertificatePassword
            $_.cmMsDeployPackageUrl.value = $cmMsDeployPackageUrl
            $_.cdMsDeployPackageUrl.value = $cdMsDeployPackageUrl
            $_.cdMsDeployPackageUrl.value = $cdMsDeployPackageUrl
            $_.prcMsDeployPackageUrl.value = $prcMsDeployPackageUrl
            $_.repMsDeployPackageUrl.value = $repMsDeployPackageUrl
            $_.xcRefDataMsDeployPackageUrl.value = $xcRefDataMsDeployPackageUrl
            $_.xcCollectMsDeployPackageUrl.value = $xcCollectMsDeployPackageUrl
            $_.xcSearchMsDeployPackageUrl.value = $xcSearchMsDeployPackageUrl
            $_.maOpsMsDeployPackageUrl.value = $maOpsMsDeployPackageUrl
            $_.maRepMsDeployPackageUrl.value = $maRepMsDeployPackageUrl
            $_.modules.value.items[0].parameters.cdSxaMsDeployPackageUrl = $sxaCDMsDeployPackageUrl
            $_.modules.value.items[0].parameters.cmSxaMsDeployPackageUrl = $sxaMsDeployPackageUrl
            $_.modules.value.items[0].parameters.speMsDeployPackageUrl = $speMsDeployPackageUrl
            $_.modules.value.items[0].templateLink = $sxaTemplateLink
            $_.modules.value.items[1].parameters.habitatWebsiteCdMsDeployPackageUrl = $habitatWebsiteCDdeployPackageUrl
            $_.modules.value.items[1].parameters.habitatWebsiteCmMsDeployPackageUrl = $habitatWebsiteDeployPackageUrl
            $_.modules.value.items[1].templateLink = $habitatWebsiteTemplateLink
            $_.modules.value.items[2].parameters.habitatXconnectDeployPackageUrl = $habitatXconnectDeployPackageUrl
            $_.modules.value.items[2].templateLink = $habitatXconnectTemplateLink
            $_.modules.value.items[3].parameters.msDeployPackageUrl = $msDeployPackageUrl
            $_.modules.value.items[3].templateLink = $bootloaderTemplateLink
        }
    }  
}

# Apply the azuredeploy.parameters JSON schema to the azuredeploy.parameters.json file

if ($definstall -eq $true) {
    $azuredeployConfig | ConvertTo-Json -Depth 20 | Set-Content $([IO.Path]::Combine($topology, 'azuredeploy.parameters.json'))
}
else {
    $azuredeployConfig | ConvertTo-Json -Depth 20 | Set-Content $([IO.Path]::Combine($topology, 'azuredeploy.parametersWOdef.json'))
}