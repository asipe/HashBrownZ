Set-StrictMode -Version 'Latest'

$ErrorActionPreference = 'Stop'

$testDir = Split-Path $script:MyInvocation.MyCommand.Path -Parent
$hbzModule = Join-Path $testDir '..\HashBrownZ\HashBrownZ.psm1'
$pesterModulePath = Join-Path $testDir '..\..\thirdparty\pester_bin\Pester.psm1'

Import-Module -Name $hbzModule,$pesterModulePath -Force

Function Set-TestFileContent ($contents) {
  $path = Join-Path $TestDrive 'file1.txt'
  if (Test-Path -Path $path -PathType Leaf) {
    Remove-Item -Path $path -Force
  }
  New-Item -Path $path -Value $contents -ItemType File | Out-Null
  $path | Write-Output
}

Describe 'Convert-HBZBytesToHexString' {
  Context 'usage' {
    It 'empty bytes gives empty string' {
      Convert-HBZBytesToHexString -Bytes @() | Should Be ''
    }

    It 'works with single byte' {
      Convert-HBZBytesToHexString -Bytes @(1) | Should Be '01'
    }

    It 'works with multiple bytes' {
      Convert-HBZBytesToHexString -Bytes @(125, 99, 145, 100, 245, 246) | Should Be '7D639164F5F6'
    }
  }
}

Describe 'Get-HBZS3FileMD5Hash' {
  Context 'usage' {
    It 'calculates md5 has for empty file' {
      $path = Set-TestFileContent -Contents ''
      Get-HBZS3FileMd5Hash -Path $path | Should Be 'D41D8CD98F00B204E9800998ECF8427E'
    }

    It 'calculates md5 hash for file with data' {
      $path = Set-TestFileContent -Contents 'hello world'
      Get-HBZS3FileMd5Hash -Path $path | Should Be '5EB63BBBE01EEED093CB22BB8F5ACDC3'
    }
  }
}

Describe 'Get-HBZS3FileMultipartMD5Hash' {
  Context 'usage' {
    It 'calculates an s3 md5 multipart hash for an empty file' {
      $path = Set-TestFileContent -Contents ''
      Get-HBZS3FileMultipartMD5Hash -Path $path -PartSize 5000| Should Be 'D41D8CD98F00B204E9800998ECF8427E-0'
    }

    It 'calculates an S3 multipart md5 hash for a file with data and a part size larger than the file size' {
      $path = Set-TestFileContent -Contents 'hello world'
      Get-HBZS3FileMultipartMD5Hash -Path $path -PartSize 5000 | Should Be '241D8A27C836427BD7F04461B60E7359-1'
    }

    It 'calculates an S3 multipart md5 hash for a file with data and a part size smaller than the file size' {
      $path = Set-TestFileContent -Contents 'hello world'
      Get-HBZS3FileMultipartMD5Hash -Path $path -PartSize 1 | Should Be '9434244CB9AB84D3696336D9F23029EC-11'
    }

    It 'calculates an S3 multipart md5 hash for a file with data and a part size smaller than the file size' {
      $path = Set-TestFileContent -Contents 'hello world'
      Get-HBZS3FileMultipartMD5Hash -Path $path -PartSize 2 | Should Be '8F3F87F705064D704B5F7B9F9F9D116F-6'
    }

    It 'calculates an S3 multipart md5 hash for a file with data and a part size equal to the file size' {
      $path = Set-TestFileContent -Contents 'hello world'
      $file = Get-ChildItem -LiteralPath $path
      Get-HBZS3FileMultipartMD5Hash -Path $path -PartSize ($file.Length) | Should Be '241D8A27C836427BD7F04461B60E7359-1'
    }
  }
}