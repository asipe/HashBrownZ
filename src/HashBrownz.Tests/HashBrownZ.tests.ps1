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

Describe 'ConvertFrom-HBZS3FileMultipartETag' {
  Context 'usage' {
    It 'returns details with a single digit part size' {
      $result = ConvertFrom-HBZS3FileMultipartETag -ETag 'hash-3' 
      $result.Hash | Should Be 'hash'
      $result.Parts | Should Be 3
    }

    It 'returns details multiple digit part size' {
      $result = ConvertFrom-HBZS3FileMultipartETag 'hash-345' 
      $result.Hash | Should Be 'hash'
      $result.Parts | Should Be 345
    }

    It 'throws if not in correct format' {
      { ConvertFrom-HBZS3FileMultipartETag 'hash' } | Should Throw 'Invalid Format'
    }
  }
}

InModuleScope HashBrownz {
  Describe 'Get-HBZS3FileMultipartMD5HashPossiblePartSize' {
    Context 'usage' {
      @(@{FileLength = 0; Parts = 1; Increment = 1048576; Expected = @() },
        @{FileLength = 1; Parts = 1; Increment = 1048576; Expected = @(1048576) },
        @{FileLength = 1; Parts = 1; Increment = 1; Expected = @(1) },
        @{FileLength = 200; Parts = 100; Increment = 1; Expected = @(2) },
        @{FileLength = 200; Parts = 100; Increment = 2; Expected = @(2) },
        @{FileLength = 1; Parts = 1; Increment = 2; Expected = @(2) },
        @{FileLength = 2; Parts = 1; Increment = 1; Expected = @(2) },
        @{FileLength = 30; Parts = 3; Increment = 1; Expected = @(10, 11, 12, 13, 14) },
        @{FileLength = 30; Parts = 10; Increment = 1; Expected = @(3) },
        @{FileLength = 12044840; Parts = 2; Increment = 1048576; Expected = @(6291456, 7340032, 8388608, 9437184, 10485760, 11534336) },
        @{FileLength = 12044840; Parts = 3; Increment = 1048576; Expected = @(4194304, 5242880) },
        @{FileLength = 12044840; Parts = 4; Increment = 1048576; Expected = @(3145728) },
        @{FileLength = 100000000; Parts = 3; Increment = 1048576; Expected = @(33554432, 34603008, 35651584, 36700160, 37748736, 38797312, 39845888, 40894464, 41943040, 42991616, 44040192, 45088768, 46137344, 47185920, 48234496, 49283072) },
        @{FileLength = 100000000; Parts = 4; Increment = 1048576; Expected = @(25165824, 26214400, 27262976, 28311552, 29360128, 30408704, 31457280, 32505856) },
        @{FileLength = 16998803; Parts = 3; Increment = 1048576; Expected = @(6291456, 7340032, 8388608) },
        @{FileLength = 16998803; Parts = 1; Increment = 1048576; Expected = @(17825792) },
        @{FileLength = 1048576; Parts = 1; Increment = 1048576; Expected = @(1048576) },
        @{FileLength = 1048576; Parts = 2; Increment = 1048576; Expected = @() },
        @{FileLength = 100000000; Parts = 3; Increment = 50000000; Expected = @() },
        @{FileLength = 100000000; Parts = 2; Increment = 50000000; Expected = @(50000000) }) |
        ForEach-Object {
          It 'returns the part size in bytes for a file and etag' {
            $config = $_
            $stubFile = @{ Length = 0 }
            $stubFile.Length = $config.FileLength
            Mock -CommandName Get-ChildItem -ModuleName 'HashBrownz' -Verifiable -ParameterFilter { ($literalPath -eq 'c:\abc.txt') } -MockWith { $stubFile }
            $actual = @(Get-HBZS3FileMultipartMD5HashPossiblePartSize -Path 'c:\abc.txt' -ETag "HASH-$($config.Parts)" -PartSizeIncrementBytes $config.Increment)
  
            for ($x = 0; $x -lt $config.Expected.Length; ++$x) {
              $actual[$x] | Should Be $config.Expected[$x]
            }
            $actual.Length | Should Be $_.Expected.Length
            Assert-VerifiableMocks 
          }
        }
    }
  }
}

Describe 'Test-HBZIsS3FileMultipartETag' {
  Context 'usage' {
    It 'returns true if etag is in s3 multipart format' {
      Test-HBZIsS3FileMultipartETag -ETag 'HASH-1' | Should Be $true
    }

    It 'returns false if etag is not in s3 multiepart format' {
      Test-HBZIsS3FileMultipartETag -ETag 'HASH' | Should Be $false
    }

    It 'returns false if etag is an empty string' {
      Test-HBZIsS3FileMultipartETag -ETag '' | Should Be $false
    }
  }
}

Describe 'Get-HBZS3KeyForFile' {
  Context 'usage' {
    @(@{Args=@{LocalRoot = 'c:\data'; FilePath = 'c:\data\one.txt'; Prefix = 'a'}; Expected = 'a/one.txt'},
      @{Args=@{LocalRoot = 'C:\data'; FilePath = 'c:\data\one.txt'; Prefix = 'a'}; Expected = 'a/one.txt'},
      @{Args=@{LocalRoot = 'c:\data\'; FilePath = 'c:\data\one.txt'; Prefix = 'a'}; Expected = 'a/one.txt'},
      @{Args=@{LocalRoot = 'c:\data\'; FilePath = 'c:\data\one.txt'; Prefix = 'a/'}; Expected = 'a/one.txt'},
      @{Args=@{LocalRoot = 'c:\data'; FilePath = 'c:\data\one.txt'; Prefix = 'a/b'}; Expected = 'a/b/one.txt'},
      @{Args=@{LocalRoot = 'c:\data'; FilePath = 'c:\data\one.txt'; Prefix = 'a/b/'}; Expected = 'a/b/one.txt'},
      @{Args=@{LocalRoot = 'c:\data'; FilePath = 'c:\data\one.txt'; Prefix = '/'}; Expected = '/one.txt'}
      @{Args=@{LocalRoot = 'c:\data'; FilePath = 'c:\data\f1\one.txt'; Prefix = 'a'}; Expected = 'a/f1/one.txt'},
      @{Args=@{LocalRoot = 'c:\data'; FilePath = 'c:\data\f1\f2\one.txt'; Prefix = 'a/b/c'}; Expected = 'a/b/c/f1/f2/one.txt'}) |
      ForEach-Object {
        It 'gets s3 key for a given file path' {
          $myargs = $_.Args
          Get-HBZS3KeyForFile @myargs | Should Be $_.Expected
        }
    }
  }
}