Function Read-Artifactory {
  <#
  .SYNOPSIS
    Downloads a file from an Artifactory repository
  .DESCRIPTION
    Downloads a file from a given Artifactory repository using the API Key either provided as an environment variable or from AWS SSM Parameter Store
  .EXAMPLE
    PS C:\> Read-Artifactory -pathToArtifact '/third-party/sophos/sophosagent.zip' -outputPath $(Join-Path $dependencyPath sophosagent.zip) -ARTIFACTORY_API_KEY 3214324123414 -ARTIFACTORY_HOST "https://davidcorp.jfrog.io/davidcorp"
    Downloads the sophosagent.zip file from the "third-party" repository to a local path using the provided API Key and URL to the Artifactory installation
  .EXAMPLE
    PS C:\> Read-Artifactory -pathToArtifact '/third-party/sophos/sophosagent.zip' -outputPath $(Join-Path $dependencyPath sophosagent.zip) -useSsm
    Downloads the sophosagent.zip file from the "third-party" repository to a local path using AWS EC2 SSM Parameter Store to retrieve the API Key and URL to the Artifactory installation
  .NOTES
    AWS EC2 SSM Parameter Store requires an AWS Profile to be created before usage
  #>
  param (
    [string]$pathToArtifact,
    [string]$outputPath,
    [Parameter(ParameterSetName = "useSSM")]
    [switch]$useSsm,
    [Parameter(ParameterSetName = "noSSM")]
    [string]$ARTIFACTORY_API_KEY,
    [Parameter(ParameterSetName = "noSSM")]
    [string]$ARTIFACTORY_HOST
  )

  if ($env:ARTIFACTORY_API_KEY) {
    $API_KEY = $env:ARTIFACTORY_API_KEY
  }
  elseif ($useSsm) {
    $API_KEY = (Get-SSMParameter -Name artifactory-api-key -WithDecryption $true).Value
  }
  else {
    $API_KEY = $ARTIFACTORY_API_KEY
  }

  if ($env:ARTIFACTORY_HOST) {
    $ARTIFACTORY_HOST = $env:ARTIFACTORY_HOST
  }
  elseif ($useSsm) {
    $ARTIFACTORY_HOST = (Get-SSMParameter -Name artifactory-host).Value
  }
  else {
    $ARTIFACTORY_HOST = $ARTIFACTORY_HOST
  }
  # because Artifactory uses HTTPS TLS1.2 we need to set this explicitly
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

  $headers = @{
    'X-JFrog-Art-Api' = $API_KEY
    "Content-Type"    = "application/json"
    "Accept"          = "application/json"
  }

  $webRequestParams = @{
    Uri     = "$ARTIFACTORY_HOST$pathToArtifact"
    Headers = $headers
    Method  = "Get"
    OutFile = $outputPath
  }

  Invoke-WebRequest @webRequestParams
}

Function Install-AwsCloudwatchConfig {
  <#
  .SYNOPSIS
    Installs a custom AWS Cloudwatch Config file on a Windows VM
  .DESCRIPTION
    Installs a custom AWS Cloudwatch Config file on a Windows VM
  .EXAMPLE
    PS C:\> Install-AwsCloudwatchConfig -pathToCloudwatchConfig c:\Cloudwatch.json
    Copies the file C:\Cloudwatch.json to the correct location for the AWS SSM agent to use. Does not validate the config itself.
  .NOTES
    General notes
  #>
  param (
    [string]$pathToCloudwatchConfig
  )

  Write-Verbose "Testing if $pathToCloudwatchConfig exists..."
  if (Test-Path -Path $pathToCloudwatchConfig) {
    Write-Verbose "Copying $pathToCloudwatchConfig to C:\Program Files\Amazon\SSM\Plugins\awsCloudWatch\AWS.EC2.Windows.CloudWatch.json ..."
    Copy-Item -Path $pathToCloudwatchConfig -Destination 'C:\Program Files\Amazon\SSM\Plugins\awsCloudWatch\AWS.EC2.Windows.CloudWatch.json'
  }
  else {
    Throw "$pathToCloudwatchConfig does not exist. Stopping execution."
  }

  Write-Verbose 'Restarting the Amazon SSM Agent...'
  Restart-Service -Name AmazonSSMAgent
}

Function Get-AwsCloudFormationStackName {
  <#
  .SYNOPSIS
    Gets AWS Cloudformation Stack Name
  .DESCRIPTION
    Executed on an AWS Windows EC2 this will return the name of the Cloudformation Stack that this EC2 is part of
  .EXAMPLE
    PS C:\> Get-AwsCloudFormationStackName
    Will return the AWS Cloudformation Stack name
  .INPUTS
    Inputs (if any)
  .OUTPUTS
    String of AWS Cloudformation Stack name
  .NOTES
    Only works on an AWS EC2
  #>
  $instanceId = (New-Object System.Net.WebClient).DownloadString("http://169.254.169.254/latest/meta-data/instance-id")
  (Get-EC2Tag -Region $(Get-AWSEc2Region) | Where-Object {$_.ResourceId -eq $instanceId} | Where-Object {$_.Key -eq 'aws:cloudformation:stack-name'}).Value
}

Function Get-AWSEc2Region {
  <#
  .SYNOPSIS
    Gets AWS Region from EC2
  .DESCRIPTION
    Executed on an AWS Windows EC2 this will return the AWS Region the EC2 is deployed to.
  .EXAMPLE
    PS C:\> Get-AwsEc2Region
    Will return the AWS Region name
  .INPUTS
    Inputs (if any)
  .OUTPUTS
    String of AWS Region name
  .NOTES
    Only works on an AWS EC2
  #>
  $doc = (Invoke-WebRequest 169.254.169.254/latest/dynamic/instance-identity/document).Content | ConvertFrom-Json
  $doc.region
}

Function Test-SQLDBExists {
  <#
  .SYNOPSIS
    Test if SQL DB exists
  .DESCRIPTION
    Tests for existence of a MS SQL database and returns boolean true or false
  .EXAMPLE
    PS C:\> Test-SQLDBExists -sqlServer sql01 -DBName customers
    Tests if a database with name "customers" exists on server SQL01
  .INPUTS
    Inputs (if any)
  .OUTPUTS
    boolean true or false
  .NOTES
    Requires Microsoft.SqlServer.Management.Smo.Server
  #>
  param (
    [string]$sqlServer,
    [string]$DBName
  )

  $exists = $false
  try {
    # we set this to null so that nothing is displayed
    $null = [reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo")

    # Get reference to database instance
    $server = New-Object ("Microsoft.SqlServer.Management.Smo.Server") $sqlServer

    foreach ($db in $server.databases) {
      Write-Host $db.name
      if ($db.name -eq $DBName) {
        $exists = $true
      }
    }
  }
  catch {
    Write-Error "Failed to connect to $sqlServer"
  }
  Write-Host $exists
  return $exists
}