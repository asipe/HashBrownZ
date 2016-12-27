Import-Module .\thirdparty\psscriptanalyzer_bin\PSScriptAnalyzer.psm1 -Force

Invoke-ScriptAnalyzer -Path .\src\HashBrownz -Recurse -ExcludeRule @('PSUseOutputTypeCorrectly')

Invoke-ScriptAnalyzer -Path .\src\HashBrownz.Tests -Recurse -ExcludeRule @('PSUseOutputTypeCorrectly',
                                                                           'PSUseShouldProcessForStateChangingFunctions')