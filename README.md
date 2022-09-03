# NuGet-PowerShell
A simple interactive utility for downloading .dlls and their dependency .dlls from NuGet

#### Dependencies:

Only has 2: `semver` and `nuget.frameworks`. To update them, you can simply run:
```
@( "semver", "nuget.frameworks" ) |
  foreach{ $_ | Get-NuGet-Dlls -Path "[root of main.ps1]\dependencies" -y }
```

**NOTE:** *They still have to exist, before running the cmdlet*, so either use mine (included in dependencies folder), or manually download them yourself to that folder

## Usage:

`Get-NuGet-Dlls [parameters - see below]`

# Parameters:

**Parameter** | **Type** | **Description**
--------------|----------|----------------
PackageName   | string   | [Mandatory, Can be Piped, Case-Insensitive] Name of NuGet Package to download/pull data from
Path          | string   | [Optional] If this option is set, the package will be downloaded to the desired path. <br/><br/>If it is not set, the script will not download the package, but will still generate an output
Range         | string   | [Optional] Range string (see [below](#range) for usage)
Group         | string   | [Optional] You can pre-enter a Target Framework/NuGet Dependency Group from the command-line. <br/><br/>*NOTE: if a child dependency doesn't have this framework/group, a prompt will be generated*
y             | switch   | [Optional] Determines if you want to use the default value for every prompt. <br/><br/>Script will only prompt you for Target Frameworks/Dependency Groups that don't match the requested group of the parent package (see [below](#y) for more info)
n             | switch   | [Optional] Do not traverse dependencies (does not download nor parse them)

## Elaboration:

### Path:

If this parameter is not set, then the script just parses the requested package (See [Return Section](#return))

### Range:

This parameter is a string in the format similar to `( [semver2] [, [semver2]* )]*` where:

**Symbol**    | **Description**
--------------|----------------
`(` `)`       | Can be any character, but they are mandatory. Meaning that `!0.0.0,1.1.1!`, `[0.0.0, )`, `[0.0.0, 1.1.1]` are all valid ranges. NOTE: This also means that `A  0.0.0, 1.1.1   Z` is also a valid range
`semver2`     | Any Semantic Versioning 2.0 compliant version number without the `v` prefix
`[...]*`      | Optional

NOTE: to specify a single version number, use `[ 1.1.1, 1.1.1 ]` or similar. `v1.1.1` will technically be parsed as `[1.1.1,)`

### y:

If this switch is present, the script will skip as many prompts as possible and resort to the default value for each (default for version will be latest stable release, and default for framework/dependency group will be the one for the parent package).

The only time a prompt will appear with the `-y` switch present is if a dependency did not have the target framework/dependency group of it's parent (for example: Parent uses net472, but Child dependency only has net461)

# Return:

Returns an array of hashtables representing the pulled/downloaded packages. It has the following keys:

## All returned hashtables:

**Key**       | **Type** | **Description**
--------------|----------|----------------
name          | string   | Name of NuGet Package downloaded/pulled

### Hashtables of dependencies:

**Key**       | **Type** | **Description**
--------------|----------|----------------
parent        | string   | Name of NuGet Package that had this package as a dependency

### Hashtables representing non-duplicate packages/dependencies:

**Key**       | **Type** | **Description**
--------------|----------|----------------
dl            | string   | The download link for the `.nupkg` file
v             | string   | Package version
framework     | string   | Target framework/dependency group selected for the package

When a package has dependencies, those dependencies may have dependencies of their own and may even reference the same dependency twice. When the script detects a dependency that it has already parsed, it will output a hashtable with only the `name` and `parent` keys filled out.

### Hashtables representing downloaded packages

**Key**       | **Type** | **Description**
--------------|----------|----------------
outfile       | string   | location of the downloaded .dll file

# Examples:

## Basic:

### Download package interactively:
```
Get-NuGet-Dlls -PackageName "NeWTonSOft.JSON" -Path "some\directory"
```
Note that the package case-sensitivity is no where near the case-sensitivity of the actual `newtonsoft.json` package
### Get download and dependency data, and skip first framework/group prompt. Do not download
```
$data = Get-NuGet-Dlls -PackageName "itext7" -Group ".NETFramework4.6.1" -y

$data.forEach({ <# do something #> })
```
Note that if the `Group` parameter is misspelled or is incorrect, a prompt will still generate

(See below for ideas on how to parse the output
### Download parent package only, do not download or parse dependencies:
```
Get-Nuget-Dlls -PackageName "System.Text.Json" -n
```

## Processing the output of the cmdlet:

### Generate an array of name-hyperlink pairs for your own custom Package Downloader
```
$data = Get-NuGet-Dlls -PackageName "itext7" -Group ".NETFramework4.6.1" -y

$data | Where { $_.dl } | Foreach { @{ $_.name = $_.dl } }
```
Output:
```
Name                           Value                                                                                                                     
----                           -----                                                                                                                     
itext7                         https://api.nuget.org/v3-flatcontainer/itext7/7.2.3/itext7.7.2.3.nupkg                                                    
itext7.commons                 https://api.nuget.org/v3-flatcontainer/itext7.commons/7.2.3/itext7.commons.7.2.3.nupkg                               
...
...
system.valuetuple              https://api.nuget.org/v3-flatcontainer/system.valuetuple/4.5.0/system.valuetuple.4.5.0.nupkg                              
portable.bouncycastle          https://api.nuget.org/v3-flatcontainer/portable.bouncycastle/1.9.0/portable.bouncycastle.1.9.0.nupkg
```

### Automate Dll Imports:
```
$data = Get-NuGet-Dlls -PackageName "System.Text.Json" -y -Path "some\directory"

$data |
  Where { $_.outfile } |
  Foreach {
    Unblock-File -Path $_
    Import-Module $_
  }
```

### Check which dependencies were included multiple times:

```
$data = Get-NuGet-Dlls -PackageName "itext7" -Group ".NETFramework4.6.1" -y

$data.name | Group-Object | Where-Object Count -GT 1
```
Output:
```
Count Name                      Group                                                                                                                    
----- ----                      -----                                                                                                                    
    2 microsoft.extensions.l... {microsoft.extensions.logging, microsoft.extensions.logging}                                                             
    3 microsoft.bcl.asyncint... {microsoft.bcl.asyncinterfaces, microsoft.bcl.asyncinterfaces, microsoft.bcl.asyncinterfaces}                            
    3 system.threading.tasks... {system.threading.tasks.extensions, system.threading.tasks.extensions, system.threading.tasks.extensions}                
    5 system.runtime.compile... {system.runtime.compilerservices.unsafe, system.runtime.compilerservices.unsafe, system.runtime.compilerservices.unsaf...
    3 microsoft.extensions.d... {microsoft.extensions.dependencyinjection.abstractions, microsoft.extensions.dependencyinjection.abstractions, microso...
    2 system.buffers            {system.buffers, system.buffers}                                                                                         
    3 system.memory             {system.memory, system.memory, system.memory}
```
