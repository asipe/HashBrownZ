Set-StrictMode -Version 'Latest'

$md5Algorithm = [Security.Cryptography.HashAlgorithm]::Create("MD5")
$bytesInAKB = 1024
$bytesInAMB = $bytesInAKB * 1024
$emptyS3ObjectData = [pscustomobject]@{
  ETag = $null
  ContentLength = $null
}

Function Convert-HBZBytesToHexString {
  [CmdletBinding()]
  Param([Parameter(Mandatory=$true)] [AllowEmptyCollection()] [byte[]]$bytes)

  [System.BitConverter]::ToString($bytes).Replace('-','') | Write-Output
}

Function Get-HBZS3FileMD5Hash {
  [CmdletBinding()]
  Param([Parameter(Mandatory=$true)] [string]$path)

  $binaryHash = $null

  $strm = [System.IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
  try { 
    $binaryHash = $md5Algorithm.ComputeHash($strm)
  } finally {
    $strm.Close()
  }

  Convert-HBZBytesToHexString -Bytes $binaryHash | Write-Output
}

Function Get-HBZS3FileMultipartMD5Hash {
  [CmdletBinding()]
  Param([Parameter(Mandatory=$true)] [string]$path,
        [Parameter(Mandatory=$true)] [int]$partSize)

  $parts = 0
  $buf = New-Object -TypeName byte[] -ArgumentList $partSize
  $binaryHash = @()

  $strm = [System.IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
  try {
    $streamLength = $strm.Length
    while (($bytesRead = $strm.Read($buf, 0, $buf.Length)) -ne 0) {
      if (($strm.Position -ne $streamLength) -and ($bytesRead -ne $buf.Length)) {
        throw 'Unable to read entire part buffer from stream'
      } else {
        $binaryHash += $md5Algorithm.ComputeHash($buf, 0, $bytesRead)
        $parts = $parts + 1
      }
    }
  } finally {
    $strm.Close()
  }

  $binaryHash = $md5Algorithm.ComputeHash($binaryHash)
  $hash = Convert-HBZBytesToHexString -Bytes $binaryHash
  '{0}-{1}' -f $hash,$parts | Write-Output
}

Function ConvertFrom-HBZS3FileMultipartETag {
  [CmdletBinding()]
  Param([Parameter(Mandatory=$true)] [string]$etag) 

  $parts = $etag -split '-'

  if ($parts.Length -ne 2) {
    throw 'Invalid Format'
  }

  $result = [pscustomobject]@{
    Hash = $parts[0]
    Parts = $parts[1]
  }

  $result | Write-Output
}

Function Get-HBZS3FileMultipartMD5HashPossiblePartSize {
  [CmdletBinding()]
  Param([Parameter(Mandatory=$true)] [string]$path,
        [Parameter(Mandatory=$true)] [string]$etag,
        [Parameter(Mandatory=$false)] [int]$partSizeIncrementBytes = $bytesInAMB)

  $parts = (ConvertFrom-HBZS3FileMultipartETag -etag $etag).Parts
  $fileLength = (Get-ChildItem -LiteralPath $path).Length
  $increment = 1

  while ($true) {
    $individualPartSize = $increment * $partSizeIncrementBytes
    $totalPartSize = $individualPartSize * $parts
    $fileLengthRemaining = $fileLength - $totalPartSize
    $overage = $fileLengthRemaining + $individualPartSize

    if (($fileLengthRemaining -le 0) -and ($overage -gt 0)) {
      $individualPartSize | Write-Output

      if ($parts -eq 1) {
        break;
      }
    }

    if ($overage -le 0) {
      break;
    }

    $increment += 1
  }
}

Function Test-HBZIsS3FileMultipartETag {
  [CmdletBinding()]
  Param([Parameter(Mandatory=$true)] [AllowEmptyString()] [string]$etag) 

  $etag -match '-' | Write-Output
}

Function Get-HBZS3KeyForFile {
  [CmdletBinding()]
  Param([Parameter(Mandatory=$true)] [string]$localRoot,
        [Parameter(Mandatory=$true)] [string]$filePath,
        [Parameter(Mandatory=$true)] [AllowEmptyString()] [string]$prefix) 

  if ($localRoot[-1] -ne '\') {
    $localRoot += '\'
  }

  if (($prefix.Length -gt 0) -and ($prefix[-1] -ne '/')) {
    $prefix += '/'
  }

  $key = $filePath -ireplace ([System.Text.RegularExpressions.Regex]::Escape($localRoot)),''
  $key = $key.Replace('\', '/')
  '{0}{1}' -f $prefix,$key | Write-Output
}

Function Get-HBZPathForS3Key {
  [CmdletBinding()]
  Param([Parameter(Mandatory=$true)] [string]$localRoot,
        [Parameter(Mandatory=$true)] [AllowEmptyString()] [string]$prefix,
        [Parameter(Mandatory=$true)] [string]$s3Key)
  $path = $s3Key
  $prefix = $prefix -replace '^/',''
  if ($prefix.Length -gt 0) {
    $path = $s3Key.Replace($prefix,'')
  }
  $path = $path.Replace('/','\')
  $path = $path -replace '^\\',''
  Join-Path $localRoot $path | Write-Output
}

Function Get-HBZS3ObjectMetaData {
  [CmdletBinding()]
  Param([Parameter(Mandatory=$true)] [string]$bucketName,
        [Parameter(Mandatory=$true)] [string]$key) 
  
  try {
    Get-S3ObjectMetaData -BucketName $bucketName -Key $key | Write-Output
  } catch {
    $msg = $_.ToString()
    Write-Debug -Message $msg
    if ($msg -notmatch 'Http Status Code NotFound') {
      throw $msg
    }
  }
}

Function Get-HBZS3ObjectData {
  [CmdletBinding()]
  Param([Parameter(Mandatory=$true)] [string]$bucketName,
        [Parameter(Mandatory=$true)] [string]$key) 
  
  $meta = Get-HBZS3ObjectMetaData -BucketName $bucketName -Key $key

  $result = [pscustomobject]@{
    ETag = $null
    ContentLength = $null
  }

  if ($null -ne $meta) {
    $result.ETag = $meta.ETag.Replace('"', '').ToUpper()
    $result.ContentLength = $meta.ContentLength
  }

  $result | Write-Output
}

Function Find-HBZS3FileHash {
  [CmdletBinding()]
  Param([Parameter(Mandatory=$true)] [string]$path,
        [Parameter(Mandatory=$true)] [AllowEmptyString()] [string]$etag) 

  if (Test-HBZIsS3FileMultipartETag -ETag $etag) {
    Get-HBZS3FileMultipartMD5HashPossiblePartSize -Path $path -ETag $etag |
      ForEach-Object { Get-HBZS3FileMultipartMD5Hash -Path $path -PartSize $_ } |
      Where-Object { $_ -eq $etag } |
      Select-Object -First 1 |
      Write-Output
  } else {
    Get-HBZS3FileMD5Hash -Path $path | Write-Output
  }
}

Function Get-HBZResultStatus {
  [CmdletBinding()]
  Param([Parameter(Mandatory=$true)] [bool]$areEqual,
        [Parameter(Mandatory=$true)] [AllowNull()] [object]$currentError,
        [Parameter(Mandatory=$true)] [AllowNull()] [AllowEmptyString()] [string]$s3ETag)

    $status = 'SAME'

    if ($null -ne $currentError) {
      $status = 'ERROR'
    } elseif (($null -eq $s3ETag) -or ('' -eq $s3ETag)) {
      $status = 'MISSINGS3'
    } elseif (!$areEqual) {
      $status = 'DIFFERENT'
    }

    $status | Write-Output
}

Function Compare-HBZFileToS3Object {
  [CmdletBinding()]
  Param([Parameter(Mandatory=$true)] [string]$localRoot,
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)] [object]$file,
        [Parameter(Mandatory=$true)] [string]$bucketName,
        [Parameter(Mandatory=$true)] [AllowEmptyString()] [string]$prefix) 

  Process {
    $localPath = $file.FullName
    $localLength = $file.Length
    $areEqual = $false
    $localETag = $currentError = $null
    $s3ObjectData = $emptyS3ObjectData

    try {
      $key = Get-HBZS3KeyForFile -LocalRoot $localRoot -FilePath $localPath -Prefix $prefix
      $s3ObjectData = Get-HBZS3ObjectData -BucketName $bucketName -Key $key 

      if ($s3ObjectData.ContentLength -eq $localLength) {
        $localETag = Find-HBZS3FileHash -Path $localPath -ETag $s3ObjectData.ETag
      } 

      $areEqual = (($s3ObjectData.ContentLength -eq $localLength) -and 
                   (($s3ObjectData.ETag -eq $localETag) -and (($null -ne $s3ObjectData.ETag) -and ($null -ne $localETag))))
    } catch {
      $currentError = $_
    }

    [pscustomobject]@{
      AreEqual = $areEqual
      Status = Get-HBZResultStatus -AreEqual $areEqual -CurrentError $currentError -S3ETag $s3objectData.ETag
      LocalPath = $localPath
      LocalETag = $localETag
      LocalLength = $localLength
      S3Key = $key
      S3ETag = $s3ObjectData.ETag
      S3Length = $s3ObjectData.ContentLength
      Error = $currentError
    } | Write-Output
  }
}

Function Test-HBZFileForS3Object {
  [CmdletBinding()]
  Param([Parameter(Mandatory=$true, ValueFromPipeline=$true)] [object]$s3Object,
        [Parameter(Mandatory=$true)] [string]$localRoot,
        [Parameter(Mandatory=$true)] [string]$prefix)

  Process {
    $path = Get-HBZPathForS3Key -LocalRoot $localRoot -Prefix $prefix -S3Key $s3Object.Key

    [pscustomobject]@{
      Exists = Test-Path $path
      S3Key = $s3Object.Key
      LocalPath = $path
    } | Write-Output
  }
}

Export-ModuleMember -Function *